/* bq76952_emul.c - behavioural emulator of the TI BQ76952 (see bq76952_emul.h).
 *
 * Register and subcommand memory handling adapted from Libre Solar bq769x2_emul.c
 * (Copyright (c) The Libre Solar Project Contributors, Apache-2.0); register map from
 * Libre Solar bq769x2_registers.h (unmodified, libresolar/). Protection and FET behaviour
 * written for Solaris from the BQ769x2 data memory semantics.
 */
#include "bq76952_emul.h"
#include "bq769x2_registers.h"
#include "solaris_config.h"

#include <math.h>
#include <string.h>

#define DIRECT_SIZE 0x80
#define DATA_SIZE   0x9400

static struct {
    uint8_t direct[DIRECT_SIZE];
    uint8_t data[DATA_SIZE];          /* subcommand responses and data memory (no overlap) */
    uint16_t mfg_status;
    uint16_t cb_active;
    int cfgupdate, fets_off;
    uint8_t ssA, ssB, saA, saB;       /* safety status (faults) / alerts */
    double tAlert[16], tRec[16];      /* per protection: time in alert, time recovering */
    uint8_t chg, dsg;
    uint16_t alarm_latched;
    uint32_t seq, ack, lastWr;
    double t;
} E;

enum { P_CUV, P_COV, P_OCC, P_OCD1, P_SCD, P_UTC, P_UTD, P_OTC, P_OTD, P_N };

/* ---------- data memory helpers ---------- */
static void dm_u1(uint16_t a, uint8_t v) { E.data[a] = v; }
static void dm_u2(uint16_t a, uint16_t v) { E.data[a] = v & 0xFF; E.data[a + 1] = v >> 8; }
static uint8_t g_u1(uint16_t a) { return E.data[a]; }
static int8_t g_i1(uint16_t a) { return (int8_t)E.data[a]; }
static uint16_t g_u2(uint16_t a) { return (uint16_t)(E.data[a] | E.data[a + 1] << 8); }
static int16_t g_i2(uint16_t a) { return (int16_t)g_u2(a); }
static void d_i2(uint8_t r, long v) {
    if (v > 32767) v = 32767;
    if (v < -32768) v = -32768;
    E.direct[r] = (uint8_t)(v & 0xFF); E.direct[r + 1] = (uint8_t)((v >> 8) & 0xFF);
}

static void load_otp(void) {
    static const uint8_t pins[9] = SOL_PIN_CONFIG;
    memset(E.data, 0, sizeof E.data);
    dm_u1(BQ769X2_SET_CONF_DA, SOL_DA_CONFIG);
    dm_u2(BQ769X2_SET_CONF_VCELL_MODE, SOL_USED_CELLS);
    dm_u1(BQ769X2_SET_PROT_ENABLED_A, SOL_PROT_ENABLED_A);
    dm_u1(BQ769X2_SET_PROT_ENABLED_B, SOL_PROT_ENABLED_B);
    dm_u2(BQ769X2_SET_MFG_STATUS_INIT, SOL_MFG_STATUS_INIT);
    dm_u1(BQ769X2_PROT_COV_THRESHOLD, SOL_COV_THRESHOLD);
    dm_u1(BQ769X2_PROT_COV_RECOV_HYST, SOL_COV_HYST);
    dm_u2(BQ769X2_PROT_COV_DELAY, SOL_COV_DELAY);
    dm_u1(BQ769X2_PROT_CUV_THRESHOLD, SOL_CUV_THRESHOLD);
    dm_u1(BQ769X2_PROT_CUV_RECOV_HYST, SOL_CUV_HYST);
    dm_u2(BQ769X2_PROT_CUV_DELAY, SOL_CUV_DELAY);
    dm_u1(BQ769X2_PROT_OCC_THRESHOLD, SOL_OCC_THRESHOLD);
    dm_u1(BQ769X2_PROT_OCC_DELAY, SOL_OCC_DELAY);
    dm_u2(BQ769X2_PROT_OCC_RECOVERY, (uint16_t)(int16_t)SOL_OCC_RECOVERY_MA);
    dm_u1(BQ769X2_PROT_OCD1_THRESHOLD, SOL_OCD1_THRESHOLD);
    dm_u1(BQ769X2_PROT_OCD1_DELAY, SOL_OCD1_DELAY);
    dm_u2(BQ769X2_PROT_OCD_RECOV_THRESHOLD, 200);
    dm_u1(BQ769X2_PROT_SCD_THRESHOLD, SOL_SCD_THRESHOLD);
    dm_u1(BQ769X2_PROT_SCD_DELAY, SOL_SCD_DELAY);
    dm_u1(BQ769X2_PROT_SCD_RECOV_TIME, SOL_SCD_RECOV_TIME_S);
    dm_u1(BQ769X2_PROT_OTC_THRESHOLD, (uint8_t)(int8_t)SOL_OTC_THRESHOLD);
    dm_u1(BQ769X2_PROT_OTC_RECOVERY, (uint8_t)(int8_t)SOL_OTC_RECOVERY);
    dm_u1(BQ769X2_PROT_OTD_THRESHOLD, (uint8_t)(int8_t)SOL_OTD_THRESHOLD);
    dm_u1(BQ769X2_PROT_OTD_RECOVERY, (uint8_t)(int8_t)SOL_OTD_RECOVERY);
    dm_u1(BQ769X2_PROT_UTC_THRESHOLD, (uint8_t)(int8_t)SOL_UTC_THRESHOLD);
    dm_u1(BQ769X2_PROT_UTC_RECOVERY, (uint8_t)(int8_t)SOL_UTC_RECOVERY);
    dm_u1(BQ769X2_PROT_UTD_THRESHOLD, (uint8_t)(int8_t)SOL_UTD_THRESHOLD);
    dm_u1(BQ769X2_PROT_UTD_RECOVERY, (uint8_t)(int8_t)SOL_UTD_RECOVERY);
    dm_u1(BQ769X2_PROT_OTC_DELAY, SOL_OT_UT_DELAY_S);
    dm_u1(BQ769X2_PROT_OTD_DELAY, SOL_OT_UT_DELAY_S);
    dm_u1(BQ769X2_PROT_UTC_DELAY, SOL_OT_UT_DELAY_S);
    dm_u1(BQ769X2_PROT_UTD_DELAY, SOL_OT_UT_DELAY_S);
    dm_u1(BQ769X2_PROT_RECOVERY_TIME, SOL_RECOVERY_TIME_S);
    for (int i = 0; i < 9; i++) dm_u1(BQ769X2_SET_CONF_CFETOFF + i, pins[i]);
}

void bqe_init(void) {
    memset(&E, 0, sizeof E);
    load_otp();
    E.mfg_status = g_u2(BQ769X2_SET_MFG_STATUS_INIT);
    E.alarm_latched = 0x0600;                         /* INITSTART | INITCOMP after power-on */
}

static void update_battery_status(void) {             /* Battery Status reflects mode changes at once */
    uint16_t bs = (uint16_t)(E.cfgupdate ? 0x0001 : 0) | (uint16_t)((E.ssA | E.ssB) ? 0x0800 : 0);
    E.direct[BQ769X2_CMD_BATTERY_STATUS] = bs & 0xFF;  E.direct[BQ769X2_CMD_BATTERY_STATUS + 1] = bs >> 8;
}

/* ---------- subcommands ---------- */
static void respond(uint16_t addr, const uint8_t *bytes, uint8_t n) {
    memcpy(&E.data[addr], bytes, n);
}
static void subcmd_cmd(uint16_t sc) {                 /* command-only subcommands */
    switch (sc) {
    case BQ769X2_SUBCMD_SET_CFGUPDATE: E.cfgupdate = 1; break;
    case BQ769X2_SUBCMD_EXIT_CFGUPDATE: E.cfgupdate = 0; break;
    case BQ769X2_SUBCMD_FET_ENABLE: E.mfg_status ^= 0x0010; break;
    case BQ769X2_SUBCMD_ALL_FETS_OFF: E.fets_off = 1; break;
    case BQ769X2_SUBCMD_ALL_FETS_ON: E.fets_off = 0; break;
    case BQ769X2_SUBCMD_RESET: bqe_init(); break;
    default: break;                                   /* SLEEP_DISABLE etc.: accepted, no effect */
    }
    update_battery_status();
}
static uint8_t resp_len(uint16_t sc) {                /* bytes returned by a subcommand read */
    switch (sc) {
    case BQ769X2_SUBCMD_DEVICE_NUMBER: case BQ769X2_SUBCMD_MFG_STATUS:
    case BQ769X2_SUBCMD_CB_ACTIVE_CELLS: return 2;
    case BQ769X2_SUBCMD_FW_VERSION: return 6;
    default: return 4;                                /* data memory: as Libre Solar's emulator */
    }
}
static void prepare_read(uint16_t sc) {               /* fill the response for subcommand sc */
    uint8_t b[6];
    if (sc == BQ769X2_SUBCMD_DEVICE_NUMBER) { b[0] = 0x95; b[1] = 0x76; respond(sc, b, 2); }  /* 0x7695 */
    else if (sc == BQ769X2_SUBCMD_FW_VERSION) { memset(b, 0, 6); b[0] = 0x76; b[1] = 0x95; respond(sc, b, 6); }
    else if (sc == BQ769X2_SUBCMD_MFG_STATUS) { b[0] = E.mfg_status & 0xFF; b[1] = E.mfg_status >> 8; respond(sc, b, 2); }
    else if (sc == BQ769X2_SUBCMD_CB_ACTIVE_CELLS) { b[0] = E.cb_active & 0xFF; b[1] = E.cb_active >> 8; respond(sc, b, 2); }
}

void bqe_i2c_write(uint8_t reg, const uint8_t *d, uint8_t n) {
    if (reg >= DIRECT_SIZE || reg + n > DIRECT_SIZE) return;
    if (reg == BQ769X2_CMD_ALARM_STATUS) {             /* write 1s to clear latched alarm bits */
        uint16_t m = d[0] | (n > 1 ? d[1] << 8 : 0);
        E.alarm_latched &= (uint16_t)~m;
        return;
    }
    memcpy(&E.direct[reg], d, n);
    uint16_t sc = (uint16_t)(E.direct[BQ769X2_CMD_SUBCMD_UPPER] << 8 | E.direct[BQ769X2_CMD_SUBCMD_LOWER]);
    if (reg == BQ769X2_SUBCMD_DATA_CHECKSUM && n >= 2) {
        /* checksum + length written: execute a write with data (data memory or subcommand) */
        uint8_t len = E.direct[BQ769X2_SUBCMD_DATA_LENGTH];
        if (len < BQ769X2_SUBCMD_OVERHEAD_BYTES || len - BQ769X2_SUBCMD_OVERHEAD_BYTES > 32) return;
        uint8_t nd = len - BQ769X2_SUBCMD_OVERHEAD_BYTES;
        uint8_t cs = E.direct[BQ769X2_CMD_SUBCMD_LOWER] + E.direct[BQ769X2_CMD_SUBCMD_UPPER];
        for (int i = 0; i < nd; i++) cs += E.direct[BQ769X2_SUBCMD_DATA_START + i];
        if ((uint8_t)~cs != E.direct[BQ769X2_SUBCMD_DATA_CHECKSUM]) return;   /* chip ignores bad checksum */
        if (BQ769X2_IS_DATA_MEM_REG_ADDR(sc)) {
            if (!E.cfgupdate) return;                 /* data memory writable only in CONFIG_UPDATE */
            memcpy(&E.data[sc], &E.direct[BQ769X2_SUBCMD_DATA_START], nd);
        } else if (sc == BQ769X2_SUBCMD_CB_ACTIVE_CELLS && nd >= 2) {
            E.cb_active = E.direct[BQ769X2_SUBCMD_DATA_START] | E.direct[BQ769X2_SUBCMD_DATA_START + 1] << 8;
        }
        return;
    }
    if (reg == BQ769X2_CMD_SUBCMD_LOWER && n == 2) {
        /* subcommand / data memory address written: execute (command-only) and prepare a read */
        if (!BQ769X2_IS_DATA_MEM_REG_ADDR(sc)) { subcmd_cmd(sc); prepare_read(sc); }
        if (sc >= DATA_SIZE) return;
        uint8_t nd = resp_len(sc);
        memcpy(&E.direct[BQ769X2_SUBCMD_DATA_START], &E.data[sc], nd);
        uint8_t cs = E.direct[BQ769X2_CMD_SUBCMD_LOWER] + E.direct[BQ769X2_CMD_SUBCMD_UPPER];
        for (int i = 0; i < nd; i++) cs += E.direct[BQ769X2_SUBCMD_DATA_START + i];
        E.direct[BQ769X2_SUBCMD_DATA_CHECKSUM] = (uint8_t)~cs;
        E.direct[BQ769X2_SUBCMD_DATA_LENGTH] = nd + BQ769X2_SUBCMD_OVERHEAD_BYTES;
    }
}

void bqe_i2c_read(uint8_t reg, uint8_t *d, uint8_t n) {
    for (int i = 0; i < n; i++) d[i] = (reg + i < DIRECT_SIZE) ? E.direct[reg + i] : 0;
}

/* ---------- protections ---------- */
/* fault set after the condition persists for 'delay'; cleared after 'rec' persists for 'trec' */
static int prot(int p, int enabled, int cond, double delay, int rec, double trec, double dt,
                uint8_t *ss, uint8_t *sa, uint8_t bit) {
    int fault = (*ss & bit) != 0;
    if (!enabled) { *ss &= (uint8_t)~bit; *sa &= (uint8_t)~bit; E.tAlert[p] = E.tRec[p] = 0; return 0; }
    if (!fault) {
        if (cond) { *sa |= bit; E.tAlert[p] += dt; } else { *sa &= (uint8_t)~bit; E.tAlert[p] = 0; }
        if (E.tAlert[p] >= delay - 1e-9) { *ss |= bit; *sa &= (uint8_t)~bit; E.tAlert[p] = 0; E.tRec[p] = 0; }
    } else {
        E.tRec[p] = rec ? E.tRec[p] + dt : 0;
        if (E.tRec[p] >= trec - 1e-9) { *ss &= (uint8_t)~bit; E.tRec[p] = 0; }
    }
    return (*ss & bit) != 0;
}

void bqe_step(double dt, const double *vIn, double iChg, const double *tPinK, double tIntK,
              double vPack, double vLd, double loadRemoved, const uint8_t *wr, uint8_t *snap,
              uint8_t *fet) {
    E.t += dt;  E.seq++;
    /* host write (one per step) */
    uint32_t ws = (uint32_t)wr[0] | (uint32_t)wr[1] << 8 | (uint32_t)wr[2] << 16 | (uint32_t)wr[3] << 24;
    if (ws != 0 && ws != E.lastWr) {
        uint8_t n = wr[5] > 32 ? 32 : wr[5];
        bqe_i2c_write(wr[4], wr + 6, n);
        E.lastWr = ws;  E.ack = ws;
    }

    /* ---- measurements (as the ADC reports them) ---- */
    uint16_t used = g_u2(BQ769X2_SET_CONF_VCELL_MODE);
    uint8_t da = g_u1(BQ769X2_SET_CONF_DA);
    double ampsLsb = (da & 0x03) == 0 ? 1e-4 : (da & 0x03) == 1 ? 1e-3 : (da & 0x03) == 2 ? 1e-2 : 1e-1;
    double voltLsb = (da & 0x04) ? 0.01 : 0.001;  /* stack / PACK / LD: centivolts or mV */
    double vStack = 0, vMax = -1, vMin = 1e9;
    for (int c = 0; c < 16; c++) {
        d_i2(BQ769X2_CMD_VOLTAGE_CELL_1 + 2 * c, lround(vIn[c] * 1000.0));
        vStack += vIn[c];
        if (used & (1u << c)) { if (vIn[c] > vMax) vMax = vIn[c]; if (vIn[c] < vMin) vMin = vIn[c]; }
    }
    d_i2(BQ769X2_CMD_VOLTAGE_STACK, lround(vStack / voltLsb));
    d_i2(BQ769X2_CMD_VOLTAGE_PACK, lround(vPack / voltLsb));
    d_i2(BQ769X2_CMD_VOLTAGE_LD, lround(vLd / voltLsb));
    d_i2(BQ769X2_CMD_CURRENT_CC2, lround(iChg / ampsLsb));
    d_i2(BQ769X2_CMD_TEMP_INT, lround(tIntK * 10.0));
    double tMax = -1e9, tMin = 1e9;
    for (int p = 0; p < 9; p++) {
        d_i2(BQ769X2_CMD_TEMP_CFETOFF + 2 * p, lround(tPinK[p] * 10.0));
        uint8_t cfg = g_u1(BQ769X2_SET_CONF_CFETOFF + p);
        if ((cfg & 0x03) == 0x03 && ((cfg >> 4) & 0x03) == 0) {      /* thermistor, cell temp */
            double tc = tPinK[p] - 273.15;
            if (tc > tMax) tMax = tc;
            if (tc < tMin) tMin = tc;
        }
    }
    if (tMax < -1e8) { tMax = tIntK - 273.15; tMin = tMax; }

    /* ---- protections (suspended in CONFIG_UPDATE, as the chip) ---- */
    uint8_t enA = g_u1(BQ769X2_SET_PROT_ENABLED_A), enB = g_u1(BQ769X2_SET_PROT_ENABLED_B);
    double rec = g_u1(BQ769X2_PROT_RECOVERY_TIME);
    double rShunt = SOL_SHUNT_UOHM * 1e-6;
    if (!E.cfgupdate) {
        double cov = g_u1(BQ769X2_PROT_COV_THRESHOLD) * 0.0506, covH = g_u1(BQ769X2_PROT_COV_RECOV_HYST) * 0.0506;
        double cuv = g_u1(BQ769X2_PROT_CUV_THRESHOLD) * 0.0506, cuvH = g_u1(BQ769X2_PROT_CUV_RECOV_HYST) * 0.0506;
        prot(P_COV, enA & 0x08, vMax >= cov, g_u2(BQ769X2_PROT_COV_DELAY) * 3.3e-3, vMax < cov - covH, rec, dt, &E.ssA, &E.saA, 0x08);
        prot(P_CUV, enA & 0x04, vMin <= cuv, g_u2(BQ769X2_PROT_CUV_DELAY) * 3.3e-3, vMin > cuv + cuvH, rec, dt, &E.ssA, &E.saA, 0x04);
        double occ = g_u1(BQ769X2_PROT_OCC_THRESHOLD) * 2e-3 / rShunt;
        double occRec = g_i2(BQ769X2_PROT_OCC_RECOVERY) * 1e-3;
        prot(P_OCC, enA & 0x10, iChg >= occ, 6.6e-3 + g_u1(BQ769X2_PROT_OCC_DELAY) * 3.3e-3, iChg <= occRec, rec, dt, &E.ssA, &E.saA, 0x10);
        double ocd = g_u1(BQ769X2_PROT_OCD1_THRESHOLD) * 2e-3 / rShunt;
        double ocdRec = g_i2(BQ769X2_PROT_OCD_RECOV_THRESHOLD) * 1e-3;
        /* OCD recovery: charge current above the recovery threshold, or load removed */
        prot(P_OCD1, enA & 0x20, -iChg >= ocd, 6.6e-3 + g_u1(BQ769X2_PROT_OCD1_DELAY) * 3.3e-3,
             iChg >= ocdRec || loadRemoved > 0.5, rec, dt, &E.ssA, &E.saA, 0x20);
        static const uint16_t scdTab[] = { 10, 20, 40, 60, 80, 100, 125, 150, 175, 200, 250, 300, 350, 400, 450, 500 };
        uint8_t si = g_u1(BQ769X2_PROT_SCD_THRESHOLD) & 0x0F;
        double scd = scdTab[si] * 1e-3 / rShunt;
        double scdDelay = (g_u1(BQ769X2_PROT_SCD_DELAY) > 0 ? g_u1(BQ769X2_PROT_SCD_DELAY) - 1 : 0) * 15e-6;
        prot(P_SCD, enA & 0x80, -iChg >= scd, scdDelay, 1, g_u1(BQ769X2_PROT_SCD_RECOV_TIME), dt, &E.ssA, &E.saA, 0x80);
        prot(P_OTC, enB & 0x10, tMax >= g_i1(BQ769X2_PROT_OTC_THRESHOLD), g_u1(BQ769X2_PROT_OTC_DELAY),
             tMax <= g_i1(BQ769X2_PROT_OTC_RECOVERY), rec, dt, &E.ssB, &E.saB, 0x10);
        prot(P_OTD, enB & 0x20, tMax >= g_i1(BQ769X2_PROT_OTD_THRESHOLD), g_u1(BQ769X2_PROT_OTD_DELAY),
             tMax <= g_i1(BQ769X2_PROT_OTD_RECOVERY), rec, dt, &E.ssB, &E.saB, 0x20);
        prot(P_UTC, enB & 0x01, tMin <= g_i1(BQ769X2_PROT_UTC_THRESHOLD), g_u1(BQ769X2_PROT_UTC_DELAY),
             tMin >= g_i1(BQ769X2_PROT_UTC_RECOVERY), rec, dt, &E.ssB, &E.saB, 0x01);
        prot(P_UTD, enB & 0x02, tMin <= g_i1(BQ769X2_PROT_UTD_THRESHOLD), g_u1(BQ769X2_PROT_UTD_DELAY),
             tMin >= g_i1(BQ769X2_PROT_UTD_RECOVERY), rec, dt, &E.ssB, &E.saB, 0x02);
    }

    /* ---- autonomous FET control ---- */
    int fetEn = (E.mfg_status & 0x0010) != 0;
    int ok = fetEn && !E.cfgupdate && !E.fets_off;
    E.chg = (uint8_t)(ok && !(E.ssA & (0x08 | 0x10)) && !(E.ssB & (0x01 | 0x10 | 0x04 | 0x40)));
    E.dsg = (uint8_t)(ok && !(E.ssA & (0x04 | 0x20 | 0x40 | 0x80)) && !(E.ssB & (0x02 | 0x20 | 0x04 | 0x40)));

    /* ---- status registers ---- */
    E.direct[BQ769X2_CMD_SAFETY_ALERT_A] = E.saA;  E.direct[BQ769X2_CMD_SAFETY_STATUS_A] = E.ssA;
    E.direct[BQ769X2_CMD_SAFETY_ALERT_B] = E.saB;  E.direct[BQ769X2_CMD_SAFETY_STATUS_B] = E.ssB;
    E.direct[BQ769X2_CMD_SAFETY_ALERT_C] = 0;      E.direct[BQ769X2_CMD_SAFETY_STATUS_C] = 0;
    update_battery_status();
    E.direct[BQ769X2_CMD_FET_STATUS] = (uint8_t)(E.chg ? 0x01 : 0) | (uint8_t)(E.dsg ? 0x04 : 0);
    uint16_t raw = 0x0080 | 0x0002;                                   /* FULLSCAN | ADSCAN */
    if (E.saA || E.ssA) raw |= 0x4000;                                /* SSA */
    if (E.saB || E.ssB) raw |= 0x8000;                                /* SSBC */
    if (!E.chg) raw |= 0x0040;                                        /* XCHG */
    if (!E.dsg) raw |= 0x0020;                                        /* XDSG */
    E.alarm_latched |= raw;
    E.direct[BQ769X2_CMD_ALARM_STATUS] = E.alarm_latched & 0xFF;  E.direct[BQ769X2_CMD_ALARM_STATUS + 1] = E.alarm_latched >> 8;
    E.direct[BQ769X2_CMD_ALARM_RAW_STATUS] = raw & 0xFF;          E.direct[BQ769X2_CMD_ALARM_RAW_STATUS + 1] = raw >> 8;

    /* ---- snapshot ---- */
    uint32_t tms = (uint32_t)lround(E.t * 1000.0);
    snap[0] = 'B'; snap[1] = 'Q'; snap[2] = '7'; snap[3] = '6';
    for (int i = 0; i < 4; i++) { snap[4 + i] = (E.seq >> (8 * i)) & 0xFF; snap[8 + i] = (E.ack >> (8 * i)) & 0xFF; snap[12 + i] = (tms >> (8 * i)) & 0xFF; }
    memcpy(snap + 16, E.direct, DIRECT_SIZE);
    fet[0] = E.chg;  fet[1] = E.dsg;
}
