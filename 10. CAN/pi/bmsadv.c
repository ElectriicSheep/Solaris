/* bmsadv.c - advisory estimator set on the Raspberry Pi.
 *
 * Reads the safety BMS's CAN frames (10. CAN/bmsCan.dbc), runs the estimator generated
 * from estimator.slx once per complete measurement set, and sends the ADV_* frames.
 *
 *   CAN mode (default):  bmsadv -i vcan0            (frames via SocketCAN; canudp bridges to the PC)
 *   UDP mode (testing):  bmsadv -u 50000 -p 127.0.0.1 -r 50001
 *                        (frames as 16-byte can_frame records over UDP, no SocketCAN needed)
 *
 * Measurement set: the BMS sends, every 100 ms and in this order, f_BmsState, f_PackLimits,
 * f_PackValuesP0, f_PackStateEstimation, f_CellVoltages mux 0-3, f_CellTemperatures mux 0-4.
 * f_CellTemperatures mux 4 closes the set and triggers one estimator step (so the estimator
 * runs at the BMS's rate, independent of the Pi's clock).
 * BMS "awake": sets arriving. No set for ADV_T_STALE -> asleep: the SOC record is saved to
 * the record file (as the BMS's non-volatile memory) and ADV_Status reports InputsStale.
 * The next set after that is a "boot" (start-up SOC: record vs OCV, rest = now - save time).
 *
 * usage: bmsadv [-i ifname | -u udp_port] [-p pc_ip] [-r pc_port] [-f record_file] [-q]
 */
#define _DEFAULT_SOURCE
#include <arpa/inet.h>
#include <linux/can.h>
#include <linux/can/raw.h>
#include <math.h>
#include <net/if.h>
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <time.h>
#include <unistd.h>

#include "adv_map.h"
#include "bms_can.h"
#include "estimator.h"

#define N_GROUP 13
#define N_TEMP 26
#define ADV_T_STALE 1.0       /* s, as ADV_tStale on the platform */
#define BMS_TS 0.1            /* s, BMS measurement set period */
#define SAVE_PERIOD 60.0      /* s, periodic record save while awake */

static int g_udp_mode = 0, g_sock = -1, g_quiet = 0;
static struct sockaddr_in g_pc;

static double now_s(void) {
    struct timespec ts; clock_gettime(CLOCK_REALTIME, &ts);
    return (double)ts.tv_sec + 1e-9 * (double)ts.tv_nsec;
}

/* ---------- transport ---------- */
static int open_can(const char *ifname) {
    int s = socket(PF_CAN, SOCK_RAW, CAN_RAW);
    if (s < 0) { perror("can socket"); exit(1); }
    struct ifreq ifr; memset(&ifr, 0, sizeof ifr);
    strncpy(ifr.ifr_name, ifname, IFNAMSIZ - 1);
    if (ioctl(s, SIOCGIFINDEX, &ifr) < 0) { perror(ifname); exit(1); }
    struct sockaddr_can a; memset(&a, 0, sizeof a);
    a.can_family = AF_CAN; a.can_ifindex = ifr.ifr_ifindex;
    if (bind(s, (struct sockaddr *)&a, sizeof a) < 0) { perror("can bind"); exit(1); }
    return s;
}

static unsigned char g_out[16 * 8];
static int g_nOut = 0;

static void send_frame(uint32_t id, const uint8_t data[8]) {
    if (g_udp_mode) {                                   /* collect; flushed after the cycle */
        unsigned char *r = g_out + 16 * g_nOut++;
        memset(r, 0, 16);
        r[0] = id & 0xFF; r[1] = (id >> 8) & 0xFF; r[4] = 8;
        memcpy(r + 8, data, 8);
    } else {
        struct can_frame f; memset(&f, 0, sizeof f);
        f.can_id = id; f.len = 8; memcpy(f.data, data, 8);
        if (write(g_sock, &f, sizeof f) != sizeof f) perror("can write");
    }
}
static void flush_frames(void) {
    if (g_udp_mode && g_nOut > 0)
        sendto(g_sock, g_out, 16 * (size_t)g_nOut, 0, (struct sockaddr *)&g_pc, sizeof g_pc);
    g_nOut = 0;
}

/* ---------- SOC record file (the BMS's non-volatile memory on the Pi) ---------- */
typedef struct { double soc[N_GROUP]; double tSave; int valid; } record_t;
static const char *g_recFile = "soc_record.txt";

static record_t load_record(void) {
    record_t r; memset(&r, 0, sizeof r);
    FILE *f = fopen(g_recFile, "r");
    if (!f) return r;
    int ok = fscanf(f, "%lf", &r.tSave) == 1;
    for (int g = 0; ok && g < N_GROUP; g++) ok = fscanf(f, "%lf", &r.soc[g]) == 1;
    fclose(f);
    r.valid = ok;
    return r;
}
static void save_record(const BMS_nvmRecord *n) {
    if (!n->valid) return;                              /* SOC not initialised: keep the old record */
    char tmp[512]; snprintf(tmp, sizeof tmp, "%s.tmp", g_recFile);
    FILE *f = fopen(tmp, "w");
    if (!f) { perror(tmp); return; }
    fprintf(f, "%.3f\n", n->tSave);
    for (int g = 0; g < N_GROUP; g++) fprintf(f, "%.6f\n", n->socGroup[g]);
    fclose(f);
    rename(tmp, g_recFile);                             /* atomic replace */
}

/* ---------- measurement set ---------- */
static struct {
    double mv[16]; int vbad[16];
    double degc[30]; int tbad[30];
    double iPack; int iSeen;
    int bmsState;
} g_m;

/* ---------- advisory output ---------- */
static uint8_t g_hb = 0;
static unsigned g_missed = 0;

static void send_adv(int awake, int stale, double inputAge) {
    const BMS_seData *se = &estimator_Y.seData;
    int init = awake && se->socInitMethod > 0;
    uint8_t d[8];

    struct bms_can_adv_status_t st; memset(&st, 0, sizeof st);
    st.heartbeat = g_hb++;
    st.valid = (uint8_t)(init && !stale);
    st.soc_valid = st.valid;
    st.soh_valid = 0; st.sop_valid = 0; st.soe_valid = 0;      /* not estimated yet */
    st.inputs_stale = (uint8_t)stale;
    st.initialising = (uint8_t)(awake && !init);
    st.estimator_set = 0;                                      /* 0 = coulomb counting */
    double age = inputAge * 1000.0; if (age > 4095) age = 4095;
    st.input_age = (uint16_t)age;
    st.bms_state_echo = (uint8_t)g_m.bmsState;
    st.frames_missed = (uint16_t)g_missed;
    bms_can_adv_status_pack(d, &st, 8); send_frame(BMS_CAN_ADV_STATUS_FRAME_ID, d);

    double mn = 1e9, mx = -1e9;
    for (int g = 0; g < N_GROUP; g++) { if (se->socGroup[g] < mn) mn = se->socGroup[g]; if (se->socGroup[g] > mx) mx = se->socGroup[g]; }
    struct bms_can_adv_pack_estimates_t pe;
    pe.soc_min = init ? bms_can_adv_pack_estimates_soc_min_encode(100.0 * mn) : 0x3FFF;
    pe.soc_max = init ? bms_can_adv_pack_estimates_soc_max_encode(100.0 * mx) : 0x3FFF;
    pe.soc_sigma = 0x3FF; pe.soh_capacity = 0x3FF; pe.soh_resistance = 0x3FF;   /* not available */
    bms_can_adv_pack_estimates_pack(d, &pe, 8); send_frame(BMS_CAN_ADV_PACK_ESTIMATES_FRAME_ID, d);

    struct bms_can_adv_power_energy_t pw;
    pw.sop_discharge = 0xFFFF; pw.sop_charge = 0xFFFF; pw.soe_energy = 0xFFFF; pw.soe_percent = 0x3FFF;
    bms_can_adv_power_energy_pack(d, &pw, 8); send_frame(BMS_CAN_ADV_POWER_ENERGY_FRAME_ID, d);

    struct bms_can_adv_current_limits_t cl;
    cl.i_discharge_max = 0xFFF; cl.i_charge_max = 0xFFF; cl.horizon = 0;
    bms_can_adv_current_limits_pack(d, &cl, 8); send_frame(BMS_CAN_ADV_CURRENT_LIMITS_FRAME_ID, d);

    double pct[16]; int avail[16];
    for (int g = 0; g < 16; g++) { pct[g] = g < N_GROUP ? 100.0 * se->socGroup[g] : 0; avail[g] = init && g < N_GROUP; }
    for (int mux = 0; mux < 4; mux++) {                         /* mux 3 last: closes the cycle */
        struct bms_can_adv_group_soc_t gs; memset(&gs, 0, sizeof gs);
        map_group_soc(&gs, mux, pct, avail);
        bms_can_adv_group_soc_pack(d, &gs, 8); send_frame(BMS_CAN_ADV_GROUP_SOC_FRAME_ID, d);
    }
    flush_frames();
}

static void run_step(int awake, int boot) {
    for (int g = 0; g < N_GROUP; g++) {
        estimator_U.vGroup[g] = g_m.mv[g] / 1000.0;
        estimator_U.vValid[g] = !g_m.vbad[g];
    }
    estimator_U.iPack = g_m.iPack;
    estimator_U.iValid = (boolean_T)g_m.iSeen;
    for (int s = 0; s < N_TEMP; s++) {
        estimator_U.tSensor[s] = g_m.degc[s] + 273.15;
        estimator_U.tValid[s] = !g_m.tbad[s];
    }
    estimator_U.rtcNow = now_s();
    if (boot) {                                          /* record as the BMS's NVM at power-up */
        record_t r = load_record();
        for (int g = 0; g < N_GROUP; g++) estimator_U.nvmSoc[g] = r.soc[g];
        estimator_U.nvmTSave = r.tSave;
        estimator_U.nvmValid = (boolean_T)r.valid;
    }
    estimator_U.awake = (boolean_T)awake;
    estimator_U.boot = (boolean_T)boot;
    estimator_U.reset = 0;
    estimator_step();
}

static void on_frame(uint32_t id, const uint8_t *data, int *setComplete) {
    switch (id) {
    case BMS_CAN_F_BMS_STATE_FRAME_ID: {
        struct bms_can_f_bms_state_t m;
        if (bms_can_f_bms_state_unpack(&m, data, 8) == 0) g_m.bmsState = m.bms_state;
        break; }
    case BMS_CAN_F_PACK_VALUES_P0_FRAME_ID: {
        struct bms_can_f_pack_values_p0_t m;
        if (bms_can_f_pack_values_p0_unpack(&m, data, 8) == 0) {
            g_m.iPack = bms_can_f_pack_values_p0_current_decode(m.current); g_m.iSeen = 1; }
        break; }
    case BMS_CAN_F_CELL_VOLTAGES_FRAME_ID: {
        struct bms_can_f_cell_voltages_t m;
        if (bms_can_f_cell_voltages_unpack(&m, data, 8) == 0) map_cell_voltages(&m, g_m.mv, g_m.vbad);
        break; }
    case BMS_CAN_F_CELL_TEMPERATURES_FRAME_ID: {
        struct bms_can_f_cell_temperatures_t m;
        if (bms_can_f_cell_temperatures_unpack(&m, data, 8) == 0) {
            map_cell_temperatures(&m, g_m.degc, g_m.tbad);
            if (m.f_cell_temperatures_mux == 4) *setComplete = 1;
        }
        break; }
    default: break;
    }
}

int main(int argc, char **argv) {
    const char *ifname = "vcan0", *pc = "192.168.50.1";
    int udpPort = 0, pcPort = 50001, opt;
    while ((opt = getopt(argc, argv, "i:u:p:r:f:q")) != -1) {
        if (opt == 'i') ifname = optarg;
        else if (opt == 'u') { g_udp_mode = 1; udpPort = atoi(optarg); }
        else if (opt == 'p') pc = optarg;
        else if (opt == 'r') pcPort = atoi(optarg);
        else if (opt == 'f') g_recFile = optarg;
        else if (opt == 'q') g_quiet = 1;
        else { fprintf(stderr, "usage: %s [-i if | -u port] [-p pc_ip] [-r port] [-f record] [-q]\n", argv[0]); return 1; }
    }
    if (g_udp_mode) {
        g_sock = socket(AF_INET, SOCK_DGRAM, 0);
        struct sockaddr_in la = {0}; la.sin_family = AF_INET; la.sin_port = htons(udpPort); la.sin_addr.s_addr = INADDR_ANY;
        if (bind(g_sock, (struct sockaddr *)&la, sizeof la) < 0) { perror("udp bind"); return 1; }
        g_pc.sin_family = AF_INET; g_pc.sin_port = htons(pcPort);
        if (inet_pton(AF_INET, pc, &g_pc.sin_addr) != 1) { fprintf(stderr, "bad PC address\n"); return 1; }
        printf("bmsadv: UDP mode, listening :%d, ADV to %s:%d, record %s\n", udpPort, pc, pcPort, g_recFile);
    } else {
        g_sock = open_can(ifname);
        printf("bmsadv: CAN mode on %s, record %s\n", ifname, g_recFile);
    }
    setvbuf(stdout, NULL, _IOLBF, 0);       /* console lines appear immediately (HDMI / ssh) */
    estimator_initialize();
    memset(&g_m, 0, sizeof g_m);
    for (int i = 0; i < 16; i++) g_m.vbad[i] = 1;
    for (int i = 0; i < 30; i++) g_m.tbad[i] = 1;

    int awake = 0, prevMethod = 0;  unsigned long nSets = 0;
    double tLastSet = -1, tLastStale = 0, tLastSave = now_s(), tLastPrint = 0;
    struct pollfd pf = {g_sock, POLLIN, 0};
    for (;;) {
        if (poll(&pf, 1, 20) < 0) { perror("poll"); return 1; }
        double t = now_s();
        int setComplete = 0;
        if (pf.revents & POLLIN) {
            if (g_udp_mode) {
                unsigned char buf[16 * 64];
                ssize_t n = recv(g_sock, buf, sizeof buf, 0);
                for (ssize_t i = 0; i + 16 <= n; i += 16) {
                    uint32_t id = buf[i] | buf[i+1] << 8 | buf[i+2] << 16 | (uint32_t)buf[i+3] << 24;
                    if (id) on_frame(id & CAN_SFF_MASK, buf + i + 8, &setComplete);
                }
            } else {
                struct can_frame f;
                if (read(g_sock, &f, sizeof f) == sizeof f && !(f.can_id & CAN_EFF_FLAG))
                    on_frame(f.can_id & CAN_SFF_MASK, f.data, &setComplete);
            }
        }
        if (setComplete) {
            int boot = !awake;
            if (awake && tLastSet > 0) {
                double gap = t - tLastSet;
                if (gap > 1.5 * BMS_TS) g_missed += (unsigned)lround(gap / BMS_TS) - 1;
            }
            awake = 1;  tLastSet = t;  nSets++;
            run_step(1, boot);
            if (boot && !g_quiet) printf("[%10.1f] BMS frames arriving: start-up\n", t);
            if (!g_quiet && estimator_Y.seData.socInitMethod > 0 && prevMethod == 0)
                printf("[%10.1f] SOC initialised %s%s (rest %.0f s; -1 = no record used)\n", t,
                       estimator_Y.seData.socInitMethod == 1 ? "from the stored record" : "from OCV",
                       estimator_Y.seData.socInitMismatch ? ", MISMATCH: recharged or swapped while off?" : "",
                       estimator_Y.seData.socInitRest);
            prevMethod = estimator_Y.seData.socInitMethod;
            send_adv(1, 0, 0.0);
            g_m.iSeen = 0;
            if (t - tLastSave > SAVE_PERIOD) { save_record(&estimator_Y.seData.nvm); tLastSave = t; }
            if (!g_quiet && t - tLastPrint >= 1.0) {
                const BMS_seData *se = &estimator_Y.seData;
                double mx = se->socGroup[0];
                for (int g = 1; g < N_GROUP; g++) if (se->socGroup[g] > mx) mx = se->socGroup[g];
                printf("[%10.1f] sets %lu missed %u | BMS state %d | I %7.2f A | SOC min %6.2f %% max %6.2f %% | recal %d\n",
                       t, nSets, g_missed, g_m.bmsState, g_m.iPack, 100 * se->socPack, 100 * mx, se->socRecal);
                fflush(stdout); tLastPrint = t;
            }
        } else if (awake && t - tLastSet > ADV_T_STALE) {
            awake = 0;  prevMethod = 0;
            save_record(&estimator_Y.seData.nvm);
            if (!g_quiet) printf("[%10.1f] BMS frames stopped: record saved, estimates stale\n", t);
        }
        if (!awake && t - tLastStale >= BMS_TS) { send_adv(0, 1, tLastSet > 0 ? t - tLastSet : 4.095); tLastStale = t; }
    }
}
