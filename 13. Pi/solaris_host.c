/* solaris_host.c - Solaris advisory layer on the Raspberry Pi.
 *
 * Host of the BQ76952: reads its measurements and protection status, runs the estimator set
 * generated from 11. Estimator/estimator.slx, and sends the ADV_* CAN messages (10. CAN/
 * solarisCan.dbc) to the vehicle. The BQ76952 protects the pack and switches its FETs on its
 * own; this program never switches FETs (the pack runs without it).
 *
 *   real hardware:  solaris_host --i2c /dev/i2c-1 [--crc] [--configure] --can can0
 *   SITL:           solaris_host --sitl <PC address>          (ADV sent by UDP to the PC)
 *
 *   --i2c DEV       BQ76952 on Linux I2C bus DEV (address 0x08; --addr to change)
 *   --crc           I2C with CRC (if the chip is configured for it)
 *   --sitl HOST     emulator at HOST: snapshots in on UDP 50010, writes out to HOST:50011
 *   --configure     write solaris_config.h into the chip's RAM at start (BQ76952EVM: its OTP is
 *                   not programmed with these values). Not needed with the emulator (has them as OTP)
 *   --can IF        ADV frames on SocketCAN interface IF (can0, vcan0)
 *   --udp HOST:PORT ADV frames as UDP datagrams of Linux can_frame records, sent from port
 *                   50013 (default in SITL: <sitl host>:50001)
 *   --record FILE   SOC record file (default soc_record.txt)
 *   --quiet         no console output except events
 *
 * Timing: one cycle (read chip, estimator step, ADV out) per 100 ms - of wall-clock time on real
 * hardware, of EMULATOR time in SITL (snapshot time stamp), so the estimator integrates the same
 * time as the simulation however fast or slow it runs.
 *
 * I2C host protocol: Libre Solar bq769x2 interface layer (libresolar/, unmodified, Apache-2.0).
 */
#define _DEFAULT_SOURCE 1
#include <arpa/inet.h>
#include <linux/can.h>
#include <linux/can/raw.h>
#include <math.h>
#include <net/if.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <time.h>
#include <unistd.h>

#include "adv_map.h"
#include "bq769x2_interface.h"
#include "bq769x2_priv.h"
#include "bq769x2_registers.h"
#include "estimator.h"
#include "solaris_can.h"
#include "solaris_config.h"
#include "transport.h"

#define PERIOD_S     0.1          /* host cycle = estimator step (BMS_Ts) */
#define T_STALE_S    1.0          /* chip silent for this long -> asleep / estimates stale */
#define SAVE_PERIOD  60.0
#define N_TEMP_EST   ((int)(sizeof estimator_U.tSensor / sizeof estimator_U.tSensor[0]))

int bq_log_level = 1;
static struct bms_ic_bq769x2_config g_cfg;
static struct bms_ic_bq769x2_data g_dat;
static struct device g_dev = { "bq76952", &g_cfg, &g_dat };
static int g_quiet = 0;

static double now_s(void) { struct timespec t; clock_gettime(CLOCK_REALTIME, &t); return t.tv_sec + 1e-9 * t.tv_nsec; }

/* ---------- ADV output ---------- */
static int g_canSock = -1, g_udpSock = -1;
static struct sockaddr_in g_udpDst;
static unsigned char g_dgram[16 * 16];
static int g_nDg = 0;
static void out_frame(uint32_t id, const uint8_t d[8]) {
    if (g_canSock >= 0) {
        struct can_frame f; memset(&f, 0, sizeof f);
        f.can_id = id; f.len = 8; memcpy(f.data, d, 8);
        if (write(g_canSock, &f, sizeof f) != sizeof f) perror("can write");
    }
    if (g_udpSock >= 0 && g_nDg < 16) {
        unsigned char *r = g_dgram + 16 * g_nDg++;
        memset(r, 0, 16); r[0] = id & 0xFF; r[1] = (id >> 8) & 0xFF; r[4] = 8; memcpy(r + 8, d, 8);
    }
}
static void out_flush(void) {
    if (g_udpSock >= 0 && g_nDg) sendto(g_udpSock, g_dgram, 16 * (size_t)g_nDg, 0, (struct sockaddr *)&g_udpDst, sizeof g_udpDst);
    g_nDg = 0;
}

/* ---------- SOC record file ---------- */
static const char *g_recFile = "soc_record.txt";
typedef struct { double soc[SOL_N_GROUPS]; double tSave; int valid; } record_t;
static record_t load_record(void) {
    record_t r; memset(&r, 0, sizeof r);
    FILE *f = fopen(g_recFile, "r");
    if (!f) return r;
    int ok = fscanf(f, "%lf", &r.tSave) == 1;
    for (int g = 0; ok && g < SOL_N_GROUPS; g++) ok = fscanf(f, "%lf", &r.soc[g]) == 1;
    fclose(f); r.valid = ok;
    return r;
}
static void save_record(const BMS_nvmRecord *n) {
    if (!n->valid) return;
    char tmp[512]; snprintf(tmp, sizeof tmp, "%s.tmp", g_recFile);
    FILE *f = fopen(tmp, "w");
    if (!f) { perror(tmp); return; }
    fprintf(f, "%.3f\n", n->tSave);
    for (int g = 0; g < SOL_N_GROUPS; g++) fprintf(f, "%.6f\n", n->socGroup[g]);
    fclose(f); rename(tmp, g_recFile);
}

/* ---------- BQ76952 ---------- */
typedef struct {
    double vCell[SOL_N_GROUPS];   /* V */
    double vStack, iPack;         /* V, A discharge positive */
    double tTherm[SOL_N_THERM];   /* degC */
    uint8_t ssA, ssB, ssC, fet;
    uint16_t batStatus;
} meas_t;
static double g_ampLsb = 0.01, g_voltLsb = 0.01;

static int chip_identify(void) {
    uint16_t dn = 0;
    if (bq769x2_subcmd_read_u2(&g_dev, BQ769X2_SUBCMD_DEVICE_NUMBER, &dn)) return -1;
    uint8_t da = 0;
    if (bq769x2_datamem_read_u1(&g_dev, BQ769X2_SET_CONF_DA, &da) == 0) {
        static const double amps[4] = { 1e-4, 1e-3, 1e-2, 1e-1 };
        g_ampLsb = amps[da & 3]; g_voltLsb = (da & 4) ? 0.01 : 0.001;
    }
    uint16_t mfg = 0;
    bq769x2_subcmd_read_u2(&g_dev, BQ769X2_SUBCMD_MFG_STATUS, &mfg);
    printf("BQ76952 found: device number 0x%04X, DA config 0x%02X (current %g A, stack %g V per count), FET_EN %d\n",
           dn, da, g_ampLsb, g_voltLsb, (mfg >> 4) & 1);
    return 0;
}

static int chip_configure(void) {   /* solaris_config.h into the chip's RAM */
    static const uint8_t pins[9] = SOL_PIN_CONFIG;
    int e = bq769x2_config_update_mode(&g_dev, true);
    e |= bq769x2_datamem_write_u1(&g_dev, BQ769X2_SET_CONF_DA, SOL_DA_CONFIG);
    e |= bq769x2_datamem_write_u2(&g_dev, BQ769X2_SET_CONF_VCELL_MODE, SOL_USED_CELLS);
    e |= bq769x2_datamem_write_u1(&g_dev, BQ769X2_SET_PROT_ENABLED_A, SOL_PROT_ENABLED_A);
    e |= bq769x2_datamem_write_u1(&g_dev, BQ769X2_SET_PROT_ENABLED_B, SOL_PROT_ENABLED_B);
    e |= bq769x2_datamem_write_u2(&g_dev, BQ769X2_SET_MFG_STATUS_INIT, SOL_MFG_STATUS_INIT);
    e |= bq769x2_datamem_write_u1(&g_dev, BQ769X2_PROT_COV_THRESHOLD, SOL_COV_THRESHOLD);
    e |= bq769x2_datamem_write_u1(&g_dev, BQ769X2_PROT_COV_RECOV_HYST, SOL_COV_HYST);
    e |= bq769x2_datamem_write_u2(&g_dev, BQ769X2_PROT_COV_DELAY, SOL_COV_DELAY);
    e |= bq769x2_datamem_write_u1(&g_dev, BQ769X2_PROT_CUV_THRESHOLD, SOL_CUV_THRESHOLD);
    e |= bq769x2_datamem_write_u1(&g_dev, BQ769X2_PROT_CUV_RECOV_HYST, SOL_CUV_HYST);
    e |= bq769x2_datamem_write_u2(&g_dev, BQ769X2_PROT_CUV_DELAY, SOL_CUV_DELAY);
    e |= bq769x2_datamem_write_u1(&g_dev, BQ769X2_PROT_OCC_THRESHOLD, SOL_OCC_THRESHOLD);
    e |= bq769x2_datamem_write_u1(&g_dev, BQ769X2_PROT_OCC_DELAY, SOL_OCC_DELAY);
    e |= bq769x2_datamem_write_i2(&g_dev, BQ769X2_PROT_OCC_RECOVERY, SOL_OCC_RECOVERY_MA);
    e |= bq769x2_datamem_write_u1(&g_dev, BQ769X2_PROT_OCD1_THRESHOLD, SOL_OCD1_THRESHOLD);
    e |= bq769x2_datamem_write_u1(&g_dev, BQ769X2_PROT_OCD1_DELAY, SOL_OCD1_DELAY);
    e |= bq769x2_datamem_write_u1(&g_dev, BQ769X2_PROT_SCD_THRESHOLD, SOL_SCD_THRESHOLD);
    e |= bq769x2_datamem_write_u1(&g_dev, BQ769X2_PROT_SCD_DELAY, SOL_SCD_DELAY);
    e |= bq769x2_datamem_write_u1(&g_dev, BQ769X2_PROT_SCD_RECOV_TIME, SOL_SCD_RECOV_TIME_S);
    e |= bq769x2_datamem_write_i1(&g_dev, BQ769X2_PROT_OTC_THRESHOLD, SOL_OTC_THRESHOLD);
    e |= bq769x2_datamem_write_i1(&g_dev, BQ769X2_PROT_OTC_RECOVERY, SOL_OTC_RECOVERY);
    e |= bq769x2_datamem_write_i1(&g_dev, BQ769X2_PROT_OTD_THRESHOLD, SOL_OTD_THRESHOLD);
    e |= bq769x2_datamem_write_i1(&g_dev, BQ769X2_PROT_OTD_RECOVERY, SOL_OTD_RECOVERY);
    e |= bq769x2_datamem_write_i1(&g_dev, BQ769X2_PROT_UTC_THRESHOLD, SOL_UTC_THRESHOLD);
    e |= bq769x2_datamem_write_i1(&g_dev, BQ769X2_PROT_UTC_RECOVERY, SOL_UTC_RECOVERY);
    e |= bq769x2_datamem_write_i1(&g_dev, BQ769X2_PROT_UTD_THRESHOLD, SOL_UTD_THRESHOLD);
    e |= bq769x2_datamem_write_i1(&g_dev, BQ769X2_PROT_UTD_RECOVERY, SOL_UTD_RECOVERY);
    e |= bq769x2_datamem_write_u1(&g_dev, BQ769X2_PROT_OTC_DELAY, SOL_OT_UT_DELAY_S);
    e |= bq769x2_datamem_write_u1(&g_dev, BQ769X2_PROT_OTD_DELAY, SOL_OT_UT_DELAY_S);
    e |= bq769x2_datamem_write_u1(&g_dev, BQ769X2_PROT_UTC_DELAY, SOL_OT_UT_DELAY_S);
    e |= bq769x2_datamem_write_u1(&g_dev, BQ769X2_PROT_UTD_DELAY, SOL_OT_UT_DELAY_S);
    e |= bq769x2_datamem_write_u1(&g_dev, BQ769X2_PROT_RECOVERY_TIME, SOL_RECOVERY_TIME_S);
    for (int i = 0; i < 9; i++) e |= bq769x2_datamem_write_u1(&g_dev, BQ769X2_SET_CONF_CFETOFF + i, pins[i]);
    e |= bq769x2_config_update_mode(&g_dev, false);
    uint16_t mfg = 0;
    if (bq769x2_subcmd_read_u2(&g_dev, BQ769X2_SUBCMD_MFG_STATUS, &mfg) == 0 && !(mfg & 0x10))
        e |= bq769x2_subcmd_cmd_only(&g_dev, BQ769X2_SUBCMD_FET_ENABLE);   /* autonomous FET control */
    printf("configure: %s\n", e ? "FAILED" : "solaris_config.h written to the chip's RAM");
    return e ? -1 : 0;
}

static int chip_read(meas_t *m) {
    static const uint8_t thermPins[SOL_N_THERM] = SOL_THERM_PINS;
    int e = 0, g = 0; int16_t v;
    e |= bq769x2_direct_read_u1(&g_dev, BQ769X2_CMD_SAFETY_STATUS_A, &m->ssA);
    e |= bq769x2_direct_read_u1(&g_dev, BQ769X2_CMD_SAFETY_STATUS_B, &m->ssB);
    e |= bq769x2_direct_read_u1(&g_dev, BQ769X2_CMD_SAFETY_STATUS_C, &m->ssC);
    e |= bq769x2_direct_read_u1(&g_dev, BQ769X2_CMD_FET_STATUS, &m->fet);
    e |= bq769x2_direct_read_u2(&g_dev, BQ769X2_CMD_BATTERY_STATUS, &m->batStatus);
    for (int c = 0; c < 16 && g < SOL_N_GROUPS; c++) {
        if (!(SOL_USED_CELLS & (1u << c))) continue;
        e |= bq769x2_direct_read_i2(&g_dev, BQ769X2_CMD_VOLTAGE_CELL_1 + 2 * c, &v);
        m->vCell[g++] = v * 1e-3;
    }
    e |= bq769x2_direct_read_i2(&g_dev, BQ769X2_CMD_VOLTAGE_STACK, &v);  m->vStack = v * g_voltLsb;
    e |= bq769x2_direct_read_i2(&g_dev, BQ769X2_CMD_CURRENT_CC2, &v);    m->iPack = -v * g_ampLsb;   /* TI: charge positive */
    for (int k = 0; k < SOL_N_THERM; k++) {
        e |= bq769x2_direct_read_i2(&g_dev, BQ769X2_CMD_TEMP_CFETOFF + 2 * thermPins[k], &v);
        m->tTherm[k] = v * 0.1 - 273.15;
    }
    return e;
}

static const char *namesA[8] = { "", "", "CUV cell under-voltage", "COV cell over-voltage", "OCC over-current in charge",
                                 "OCD1 over-current in discharge", "OCD2 over-current in discharge 2", "SCD short circuit in discharge" };
static const char *namesB[8] = { "UTC under-temperature in charge", "UTD under-temperature in discharge", "UTINT die under-temperature", "",
                                 "OTC over-temperature in charge", "OTD over-temperature in discharge", "OTINT die over-temperature", "OTF FET over-temperature" };
static void report_changes(double t, const meas_t *m, const meas_t *p) {
    for (int b = 0; b < 8; b++) {
        if (((m->ssA ^ p->ssA) >> b) & 1) printf("[%10.1f] PROTECTION %s: %s\n", t, (m->ssA >> b) & 1 ? "TRIPPED" : "recovered", namesA[b]);
        if (((m->ssB ^ p->ssB) >> b) & 1) printf("[%10.1f] PROTECTION %s: %s\n", t, (m->ssB >> b) & 1 ? "TRIPPED" : "recovered", namesB[b]);
    }
    if ((m->fet ^ p->fet) & 0x05)
        printf("[%10.1f] FETs: CHG %s, DSG %s\n", t, m->fet & 1 ? "ON" : "off", m->fet & 4 ? "ON" : "off");
    if (m->ssC != p->ssC) printf("[%10.1f] Safety Status C = 0x%02X\n", t, m->ssC);
}

/* ---------- estimator + ADV ---------- */
static uint8_t g_hb = 0;
static unsigned g_missed = 0;
static void run_estimator(const meas_t *m, int boot) {
    for (int g = 0; g < SOL_N_GROUPS; g++) {
        estimator_U.vGroup[g] = m->vCell[g];
        estimator_U.vValid[g] = m->vCell[g] > 0.5 && m->vCell[g] < 5.0;    /* plausible range */
    }
    estimator_U.iPack = m->iPack;  estimator_U.iValid = 1;
    for (int k = 0; k < N_TEMP_EST; k++) {
        /* slots beyond the fitted thermistors (if the estimator has more inputs) are not sensors:
         * marked valid so they cannot block start-up; the SOC estimator does not use temperature */
        estimator_U.tSensor[k] = k < SOL_N_THERM ? m->tTherm[k] + 273.15 : 298.15;
        estimator_U.tValid[k] = k >= SOL_N_THERM || (m->tTherm[k] > -40 && m->tTherm[k] < 120);
    }
    estimator_U.rtcNow = now_s();
    if (boot) {
        record_t r = load_record();
        for (int g = 0; g < SOL_N_GROUPS; g++) estimator_U.nvmSoc[g] = r.soc[g];
        estimator_U.nvmTSave = r.tSave;  estimator_U.nvmValid = (boolean_T)r.valid;
    }
    estimator_U.awake = 1;  estimator_U.boot = (boolean_T)boot;  estimator_U.reset = 0;
    estimator_step();
}

static void send_adv(int awake, const meas_t *m, double inputAge) {
    const BMS_seData *se = &estimator_Y.seData;
    int init = awake && se->socInitMethod > 0;
    uint8_t d[8];
    struct solaris_can_adv_status_t st; memset(&st, 0, sizeof st);
    st.heartbeat = g_hb++;
    st.valid = (uint8_t)init;  st.soc_valid = (uint8_t)init;
    st.inputs_stale = (uint8_t)!awake;  st.initialising = (uint8_t)(awake && !init);
    double age = inputAge * 1000.0; if (age > 4095) age = 4095; if (age < 0) age = 0;
    st.input_age = (uint16_t)age;
    st.afe_state = (uint8_t)((m->fet & 1) | ((m->fet & 4) ? 2 : 0) | ((m->ssA | m->ssB | m->ssC) ? 4 : 0) | ((m->batStatus & 1) ? 8 : 0));
    st.frames_missed = (uint16_t)g_missed;
    solaris_can_adv_status_pack(d, &st, 8); out_frame(SOLARIS_CAN_ADV_STATUS_FRAME_ID, d);

    double mn = 1e9, mx = -1e9;
    for (int g = 0; g < SOL_N_GROUPS; g++) { if (se->socGroup[g] < mn) mn = se->socGroup[g]; if (se->socGroup[g] > mx) mx = se->socGroup[g]; }
    struct solaris_can_adv_pack_estimates_t pe;
    pe.soc_min = init ? solaris_can_adv_pack_estimates_soc_min_encode(100 * mn) : 0x3FFF;
    pe.soc_max = init ? solaris_can_adv_pack_estimates_soc_max_encode(100 * mx) : 0x3FFF;
    pe.soc_sigma = 0x3FF; pe.soh_capacity = 0x3FF; pe.soh_resistance = 0x3FF;     /* not estimated yet */
    solaris_can_adv_pack_estimates_pack(d, &pe, 8); out_frame(SOLARIS_CAN_ADV_PACK_ESTIMATES_FRAME_ID, d);
    struct solaris_can_adv_power_energy_t pw = { 0xFFFF, 0xFFFF, 0xFFFF, 0x3FFF };
    solaris_can_adv_power_energy_pack(d, &pw, 8); out_frame(SOLARIS_CAN_ADV_POWER_ENERGY_FRAME_ID, d);
    struct solaris_can_adv_current_limits_t cl = { 0xFFF, 0xFFF, 0 };
    solaris_can_adv_current_limits_pack(d, &cl, 8); out_frame(SOLARIS_CAN_ADV_CURRENT_LIMITS_FRAME_ID, d);
    struct solaris_can_adv_afe_status_t af;
    af.safety_status_a = m->ssA; af.safety_status_b = m->ssB; af.safety_status_c = m->ssC; af.fet_status = m->fet;
    af.stack_voltage = solaris_can_adv_afe_status_stack_voltage_encode(m->vStack);
    af.current = solaris_can_adv_afe_status_current_encode(m->iPack);
    solaris_can_adv_afe_status_pack(d, &af, 8); out_frame(SOLARIS_CAN_ADV_AFE_STATUS_FRAME_ID, d);
    double pct[16]; int avail[16];
    for (int g = 0; g < 16; g++) { pct[g] = g < SOL_N_GROUPS ? 100 * se->socGroup[g] : 0; avail[g] = init && g < SOL_N_GROUPS; }
    for (int mux = 0; mux < 4; mux++) {                                         /* mux 3 last */
        struct solaris_can_adv_group_soc_t gs; memset(&gs, 0, sizeof gs);
        map_group_soc(&gs, mux, pct, avail);
        solaris_can_adv_group_soc_pack(d, &gs, 8); out_frame(SOLARIS_CAN_ADV_GROUP_SOC_FRAME_ID, d);
    }
    out_flush();
}

static volatile int g_run = 1;
static void on_sig(int s) { (void)s; g_run = 0; }

int main(int argc, char **argv) {
    const char *i2cDev = NULL, *sitl = NULL, *canIf = NULL, *udpOut = NULL;
    int crc = 0, configure = 0; unsigned addr = SOL_I2C_ADDR;
    for (int a = 1; a < argc; a++) {
        if (!strcmp(argv[a], "--i2c") && a + 1 < argc) i2cDev = argv[++a];
        else if (!strcmp(argv[a], "--addr") && a + 1 < argc) addr = (unsigned)strtoul(argv[++a], NULL, 0);
        else if (!strcmp(argv[a], "--crc")) crc = 1;
        else if (!strcmp(argv[a], "--sitl") && a + 1 < argc) sitl = argv[++a];
        else if (!strcmp(argv[a], "--configure")) configure = 1;
        else if (!strcmp(argv[a], "--can") && a + 1 < argc) canIf = argv[++a];
        else if (!strcmp(argv[a], "--udp") && a + 1 < argc) udpOut = argv[++a];
        else if (!strcmp(argv[a], "--record") && a + 1 < argc) g_recFile = argv[++a];
        else if (!strcmp(argv[a], "--quiet")) g_quiet = 1;
        else if (!strcmp(argv[a], "--verbose")) bq_log_level = 3;
        else { fprintf(stderr, "usage: %s (--i2c DEV [--addr A] [--crc] | --sitl HOST) [--configure] [--can IF] [--udp HOST:PORT] [--record FILE] [--quiet]\n", argv[0]); return 1; }
    }
    if (!!i2cDev == !!sitl) { fprintf(stderr, "choose one of --i2c or --sitl\n"); return 1; }
    setvbuf(stdout, NULL, _IOLBF, 0);
    signal(SIGINT, on_sig); signal(SIGTERM, on_sig);
    g_cfg.read_bytes = tp_read;  g_cfg.write_bytes = tp_write;  g_cfg.i2c.addr = (uint16_t)addr;
    if (i2cDev ? tp_open_i2c(i2cDev, (uint8_t)addr, crc) : tp_open_sitl(sitl, 50010, 50011)) return 1;

    if (canIf) {
        g_canSock = socket(PF_CAN, SOCK_RAW, CAN_RAW);
        struct ifreq ifr; memset(&ifr, 0, sizeof ifr); strncpy(ifr.ifr_name, canIf, IFNAMSIZ - 1);
        struct sockaddr_can ca; memset(&ca, 0, sizeof ca); ca.can_family = AF_CAN;
        if (g_canSock < 0 || ioctl(g_canSock, SIOCGIFINDEX, &ifr) < 0) { perror(canIf); return 1; }
        ca.can_ifindex = ifr.ifr_ifindex;
        if (bind(g_canSock, (struct sockaddr *)&ca, sizeof ca) < 0) { perror("can bind"); return 1; }
    }
    if (!udpOut && sitl && !canIf) { static char def[128]; snprintf(def, sizeof def, "%s:50001", sitl); udpOut = def; }
    if (udpOut) {
        char host[100]; int port = 0;
        if (sscanf(udpOut, "%99[^:]:%d", host, &port) != 2) { fprintf(stderr, "--udp HOST:PORT\n"); return 1; }
        g_udpSock = socket(AF_INET, SOCK_DGRAM, 0);
        struct sockaddr_in src; memset(&src, 0, sizeof src);    /* fixed source port 50013 (Simulink filter) */
        src.sin_family = AF_INET; src.sin_port = htons(50013); src.sin_addr.s_addr = INADDR_ANY;
        if (bind(g_udpSock, (struct sockaddr *)&src, sizeof src) < 0) { perror("ADV source port 50013"); return 1; }
        g_udpDst.sin_family = AF_INET; g_udpDst.sin_port = htons((uint16_t)port);
        if (inet_pton(AF_INET, host, &g_udpDst.sin_addr) != 1) { fprintf(stderr, "bad address %s\n", host); return 1; }
    }
    printf("solaris_host: %s %s, ADV to %s%s%s, record %s\n", i2cDev ? "I2C" : "SITL", i2cDev ? i2cDev : sitl,
           canIf ? canIf : "", canIf && udpOut ? " + " : "", udpOut ? udpOut : "", g_recFile);
    estimator_initialize();

    int awake = 0, identified = 0, prevMethod = 0;
    meas_t m, prev; memset(&m, 0, sizeof m); memset(&prev, 0, sizeof prev);
    double tLast = -1, tSave = now_s(), tPrint = 0, tNext = now_s();
    uint32_t chipLast = 0;  int chipStarted = 0;
    while (g_run) {
        double t = now_s();
        double age;
        if (tp_is_sitl()) {
            /* SITL: one cycle per 100 ms of EMULATOR time (the simulation may run slower or faster
             * than real time); while the emulator is silent, wall-clock cycles report it stale */
            age = tp_poll();
            uint32_t ct = tp_chip_time_ms();
            int fresh = age >= 0 && age < T_STALE_S;
            if (fresh) {
                uint32_t d = ct - chipLast;                       /* ms since the last cycle */
                if (chipStarted && (int32_t)d < 0) chipStarted = 0;           /* emulator restarted */
                if (!chipStarted) { chipLast = ct; chipStarted = 1; }
                else {
                    const uint32_t per = (uint32_t)lround(PERIOD_S * 1000);
                    if (d < per) { usleep(2000); continue; }
                    uint32_t n = d / per;
                    if (awake && n > 1) g_missed += n - 1;
                    chipLast += n * per;
                }
            } else {
                if (t < tNext) { usleep((useconds_t)((tNext - t) * 1e6)); continue; }
                tNext = t + PERIOD_S;
            }
        } else {
            if (t < tNext) { usleep((useconds_t)((tNext - t) * 1e6)); continue; }
            tNext += PERIOD_S;
            if (t - tNext > 1.0) tNext = t + PERIOD_S;                   /* fell behind: resync */
            age = tp_poll();
        }
        int alive = tp_is_sitl() ? (age >= 0 && age < T_STALE_S) : 1;
        int ok = alive && (identified || chip_identify() == 0);
        if (ok && !identified) {
            identified = 1;
            if (configure && chip_configure()) { identified = 0; ok = 0; }
            t = now_s();  tNext = t + PERIOD_S;          /* configuring takes ~1 s: restart the cycle clock */
        }
        if (ok) ok = chip_read(&m) == 0;
        if (ok) {
            int boot = !awake;
            if (boot) printf("[%10.1f] BQ76952 answering: start-up\n", t);
            if (!tp_is_sitl() && awake && tLast > 0 && t - tLast > 1.5 * PERIOD_S) {
                g_missed += (unsigned)lround((t - tLast) / PERIOD_S) - 1;
                if (bq_log_level >= 3) printf("[%10.1f] cycle gap %.3f s\n", t, t - tLast);
            }
            awake = 1; tLast = t;
            run_estimator(&m, boot);
            if (boot) prev = m, prev.fet = (uint8_t)~m.fet;                 /* report the initial FET state */
            report_changes(t, &m, &prev); prev = m;
            int meth = estimator_Y.seData.socInitMethod;
            if (meth > 0 && prevMethod == 0)
                printf("[%10.1f] SOC initialised %s%s (rest %.0f s; -1 = no record used)\n", t, meth == 1 ? "from the stored record" : "from OCV",
                       estimator_Y.seData.socInitMismatch ? ", MISMATCH: recharged or swapped while off?" : "", estimator_Y.seData.socInitRest);
            prevMethod = meth;
            send_adv(1, &m, tp_is_sitl() ? age : 0);
            if (t - tSave > SAVE_PERIOD) { save_record(&estimator_Y.seData.nvm); tSave = t; }
            if (!g_quiet && t - tPrint >= 1.0) {
                double vmin = 9, vmax = 0, tmax = -99;
                for (int g = 0; g < SOL_N_GROUPS; g++) { if (m.vCell[g] < vmin) vmin = m.vCell[g]; if (m.vCell[g] > vmax) vmax = m.vCell[g]; }
                for (int k = 0; k < SOL_N_THERM; k++) if (m.tTherm[k] > tmax) tmax = m.tTherm[k];
                printf("[%10.1f] %5.2f V  I %7.2f A  cell %.3f-%.3f V  Tmax %4.1f C  CHG %d DSG %d  safety %02X/%02X  SOC %6.2f %%  missed %u\n",
                       t, m.vStack, m.iPack, vmin, vmax, tmax, m.fet & 1, (m.fet >> 2) & 1, m.ssA, m.ssB, 100 * estimator_Y.seData.socPack, g_missed);
                tPrint = t;
            }
        } else {
            if (awake && (t - tLast > T_STALE_S)) {
                awake = 0; prevMethod = 0; identified = 0;
                save_record(&estimator_Y.seData.nvm);
                printf("[%10.1f] BQ76952 not answering: record saved, estimates stale\n", t);
            }
            if (!awake) send_adv(0, &prev, tLast > 0 ? t - tLast : 4.095);
        }
    }
    if (awake) save_record(&estimator_Y.seData.nvm);
    printf("solaris_host: stopped, record saved\n");
    return 0;
}
