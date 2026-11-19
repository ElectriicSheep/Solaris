/* bqe_sitl.c - stand-alone SITL: a simple 13-group pack + the BQ76952 emulator, in real time,
 * talking to the Pi host (solaris_host --sitl) over the same UDP link as the Simulink platform.
 * For testing the Pi without MATLAB. The pack here is deliberately simple (OCV table + series
 * resistance, no dynamics, 25 degC): the Simscape plant in Simulink is the reference model.
 *
 * usage: bqe_sitl PI_HOST [--soc 0.8] [--current A] [--duration s]
 *                         [--fault cov|cuv|ocd|otc --fault-at s --fault-for s]
 *   PI_HOST     where solaris_host runs (snapshots to PI_HOST:50010; writes in on :50011)
 *   --current   pack current, A, discharge positive (default 5)
 */
#define _DEFAULT_SOURCE 1
#include "bq76952_emul.h"
#include "solaris_config.h"

#include <arpa/inet.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <time.h>
#include <unistd.h>

static const double socBp[11] = { 0, .1, .2, .3, .4, .5, .6, .7, .8, .9, 1 };
static const double ocvV[11] = { 2.80, 3.35, 3.48, 3.57, 3.64, 3.71, 3.80, 3.90, 4.00, 4.09, 4.18 };  /* generic NMC, placeholder */
static double ocv(double s) {
    if (s <= 0) return ocvV[0];
    if (s >= 1) return ocvV[10];
    int i = (int)(s * 10); double f = (s - socBp[i]) * 10;
    return ocvV[i] + f * (ocvV[i + 1] - ocvV[i]);
}
static double now_s(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec + 1e-9 * t.tv_nsec; }

int main(int argc, char **argv) {
    if (argc < 2) { fprintf(stderr, "usage: %s PI_HOST [--soc x] [--current A] [--duration s] [--fault cov|cuv|ocd|otc --fault-at s --fault-for s]\n", argv[0]); return 1; }
    const char *pi = argv[1], *fault = NULL;
    double soc0 = 0.8, iDis = 5, dur = 1e9, fAt = 10, fFor = 5;
    for (int a = 2; a < argc; a++) {
        if (!strcmp(argv[a], "--soc") && a + 1 < argc) soc0 = atof(argv[++a]);
        else if (!strcmp(argv[a], "--current") && a + 1 < argc) iDis = atof(argv[++a]);
        else if (!strcmp(argv[a], "--duration") && a + 1 < argc) dur = atof(argv[++a]);
        else if (!strcmp(argv[a], "--fault") && a + 1 < argc) fault = argv[++a];
        else if (!strcmp(argv[a], "--fault-at") && a + 1 < argc) fAt = atof(argv[++a]);
        else if (!strcmp(argv[a], "--fault-for") && a + 1 < argc) fFor = atof(argv[++a]);
    }
    int tx = socket(AF_INET, SOCK_DGRAM, 0), rx = socket(AF_INET, SOCK_DGRAM, 0);
    struct sockaddr_in dst = { 0 }, la = { 0 };
    dst.sin_family = AF_INET; dst.sin_port = htons(50010); inet_pton(AF_INET, pi, &dst.sin_addr);
    la.sin_family = AF_INET; la.sin_port = htons(50011); la.sin_addr.s_addr = INADDR_ANY;
    if (bind(rx, (struct sockaddr *)&la, sizeof la) < 0) { perror("bind 50011"); return 1; }
    struct timeval tv = { 0, 0 }; setsockopt(rx, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof tv);

    const double dt = 0.01, Q = 7 * 3.35 * 3600, R = 0.030 / 7;   /* group capacity (C), resistance */
    double soc[SOL_N_GROUPS];
    for (int g = 0; g < SOL_N_GROUPS; g++) soc[g] = soc0 + 0.002 * (g - 6);   /* small spread */
    bqe_init();
    uint8_t wr[BQE_WRITE_BYTES], snap[BQE_SNAP_BYTES], fet[2] = { 1, 1 }, q[64][BQE_WRITE_BYTES];
    int qn = 0; uint8_t lastFet = 0xFF;
    double t = 0, t0 = now_s();
    printf("bqe_sitl: snapshots to %s:50010, writes on :50011; SOC %.2f, %.1f A discharge%s%s\n", pi, soc0, iDis,
           fault ? ", fault " : "", fault ? fault : "");
    while (t < dur) {
        /* host writes: queue all received, apply one per step (as the Simulink block) */
        uint8_t b[64]; ssize_t n;
        while (qn < 64 && (n = recv(rx, b, sizeof b, MSG_DONTWAIT)) == BQE_WRITE_BYTES) memcpy(q[qn++], b, BQE_WRITE_BYTES);
        memset(wr, 0, sizeof wr);
        if (qn) { memcpy(wr, q[0], BQE_WRITE_BYTES); memmove(q[0], q[1], (size_t)(--qn) * BQE_WRITE_BYTES); }

        int fon = fault && t >= fAt && t < fAt + fFor;
        double iDem = iDis + ((fon && !strcmp(fault, "ocd")) ? 60 - iDis : 0);
        /* FETs: discharge needs DSG (CHG body diode conducts), charge needs CHG */
        double i = (iDem >= 0 ? fet[1] : fet[0]) ? iDem : 0;
        double vIn[16] = { 0 }, tPin[9], vStack = 0;
        for (int g = 0; g < SOL_N_GROUPS; g++) {
            soc[g] -= i * dt / Q;
            vIn[g] = ocv(soc[g]) - i * R;
            vStack += vIn[g];
        }
        if (fon && !strcmp(fault, "cov")) vIn[4] = 4.30;
        if (fon && !strcmp(fault, "cuv")) vIn[4] = 2.60;
        for (int p = 0; p < 9; p++) tPin[p] = 298.15 + ((fon && !strcmp(fault, "otc") && p == 3) ? 21 : 0);
        double vPack = (fet[0] || fet[1]) ? vStack : 0;
        bqe_step(dt, vIn, -i, tPin, 298.15, vPack, vPack, fabs(iDem) < 0.1 ? 1 : 0, wr, snap, fet);
        sendto(tx, snap, sizeof snap, 0, (struct sockaddr *)&dst, sizeof dst);
        uint8_t f = (uint8_t)(fet[0] | fet[1] << 1);
        if (f != lastFet) { printf("[%7.2f s] emulator FETs: CHG %d DSG %d  (I %.1f A)\n", t, fet[0], fet[1], i); lastFet = f; }
        t += dt;
        double wait = t0 + t - now_s();
        if (wait > 0) usleep((useconds_t)(wait * 1e6));
    }
    return 0;
}
