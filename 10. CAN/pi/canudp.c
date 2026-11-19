/* canudp.c - bridge between the PC test platform (UDP) and a SocketCAN interface.
 *
 *   PC  --UDP :50000-->  canudp  --CAN-->  vcan0 / can0   (BMS frames, 16-byte can_frame records)
 *   PC  <--UDP :50001--  canudp  <--CAN--  vcan0 / can0   (ADV_* frames from the estimator)
 *
 * Datagram format both ways: N x Linux struct can_frame (16 bytes: can_id little-endian,
 * len, 3 pad, 8 data). PC -> Pi records with can_id 0 are skipped (BMS off).
 * ADV frames (0x380-0x384) are collected; one 128-byte datagram (8 frames: Status,
 * PackEstimates, PowerEnergy, CurrentLimits, GroupSoc mux 0-3) is sent to the PC each
 * time ADV_GroupSoc mux 3 arrives (the estimator sends it last in every cycle).
 *
 * usage: canudp [-i vcan0] [-l 50000] [-p 192.168.50.1] [-r 50001]
 */
#define _DEFAULT_SOURCE
#include <arpa/inet.h>
#include <linux/can.h>
#include <linux/can/raw.h>
#include <net/if.h>
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <unistd.h>

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

int main(int argc, char **argv) {
    const char *ifname = "vcan0", *pc = "192.168.50.1";
    int lport = 50000, rport = 50001, opt;
    while ((opt = getopt(argc, argv, "i:l:p:r:")) != -1) {
        if (opt == 'i') ifname = optarg;
        else if (opt == 'l') lport = atoi(optarg);
        else if (opt == 'p') pc = optarg;
        else if (opt == 'r') rport = atoi(optarg);
        else { fprintf(stderr, "usage: %s [-i if] [-l port] [-p pc_ip] [-r port]\n", argv[0]); return 1; }
    }
    int cs = open_can(ifname);
    int us = socket(AF_INET, SOCK_DGRAM, 0);
    struct sockaddr_in la = {0}; la.sin_family = AF_INET; la.sin_port = htons(lport); la.sin_addr.s_addr = INADDR_ANY;
    if (bind(us, (struct sockaddr *)&la, sizeof la) < 0) { perror("udp bind"); return 1; }
    struct sockaddr_in ra = {0}; ra.sin_family = AF_INET; ra.sin_port = htons(rport);
    if (inet_pton(AF_INET, pc, &ra.sin_addr) != 1) { fprintf(stderr, "bad PC address %s\n", pc); return 1; }
    printf("canudp: UDP :%d -> %s, %s -> UDP %s:%d\n", lport, ifname, ifname, pc, rport);

    struct can_frame adv[8]; memset(adv, 0, sizeof adv);
    unsigned long nIn = 0, nOut = 0;
    struct pollfd pf[2] = {{us, POLLIN, 0}, {cs, POLLIN, 0}};
    for (;;) {
        if (poll(pf, 2, 1000) < 0) { perror("poll"); return 1; }
        if (pf[0].revents & POLLIN) {                        /* PC -> CAN */
            unsigned char buf[16 * 64];
            ssize_t n = recv(us, buf, sizeof buf, 0);
            for (ssize_t i = 0; i + 16 <= n; i += 16) {
                struct can_frame f; memset(&f, 0, sizeof f);
                f.can_id = (canid_t)buf[i] | (canid_t)buf[i+1] << 8 | (canid_t)buf[i+2] << 16 | (canid_t)buf[i+3] << 24;
                if (f.can_id == 0) continue;
                f.len = buf[i+4] > 8 ? 8 : buf[i+4];
                memcpy(f.data, buf + i + 8, 8);
                if (write(cs, &f, sizeof f) != sizeof f) perror("can write");
                nIn++;
            }
        }
        if (pf[1].revents & POLLIN) {                        /* CAN -> PC */
            struct can_frame f;
            if (read(cs, &f, sizeof f) != sizeof f) continue;
            canid_t id = f.can_id & CAN_SFF_MASK;
            int slot = -1;
            if (id >= 0x380 && id <= 0x383) slot = (int)(id - 0x380);
            else if (id == 0x384 && f.data[0] < 4) slot = 4 + f.data[0];
            if (slot < 0) continue;
            adv[slot] = f;
            if (slot == 7) {                                  /* GroupSoc mux 3: cycle complete */
                unsigned char out[128]; memset(out, 0, sizeof out);
                for (int k = 0; k < 8; k++) {
                    canid_t c = adv[k].can_id & CAN_SFF_MASK;
                    out[16*k] = c & 0xFF; out[16*k+1] = (c >> 8) & 0xFF;
                    out[16*k+4] = adv[k].len;
                    memcpy(out + 16*k + 8, adv[k].data, 8);
                }
                sendto(us, out, sizeof out, 0, (struct sockaddr *)&ra, sizeof ra);
                nOut++;
                if (nOut % 100 == 0) printf("canudp: %lu BMS frames in, %lu ADV datagrams out\n", nIn, nOut);
            }
        }
    }
}
