/* bq76952_emul.c - behavioural emulator of the TI BQ76952 (see bq76952_emul.h).
 *
 * Register and subcommand memory handling adapted from Libre Solar bq769x2_emul.c
 * (Copyright (c) The Libre Solar Project Contributors, Apache-2.0); register map from
 * Libre Solar bq769x2_registers.h (unmodified, libresolar/). Protection and FET behaviour
 * written for Solaris from the BQ769x2 data memory semantics.
 */
#include "bq76952_emul.h"
#include "bq769x2_registers.h"

#include <math.h>
#include <stdlib.h>
#include <string.h>

#define DIRECT_SIZE 0x80
#define DATA_SIZE   0x9400

struct BqeState {
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
    uint32_t lastI2cTxn;
    uint8_t i2cAddress, i2cTxnSeen;
    uint8_t i2cResponse[BQE_I2C_RESP_BYTES];
    double t;
    double shuntOhms;
};

static BqeState legacyState;

enum { P_CUV, P_COV, P_OCC, P_OCD1, P_SCD, P_UTC, P_UTD, P_OTC, P_OTD, P_N };

/* ---------- data memory helpers ---------- */
static void dm_u1(BqeState *s, uint16_t a, uint8_t v) { s->data[a] = v; }
static void dm_u2(BqeState *s, uint16_t a, uint16_t v) { s->data[a] = v & 0xFF; s->data[a + 1] = v >> 8; }
static uint8_t g_u1(BqeState *s, uint16_t a) { return s->data[a]; }
static int8_t g_i1(BqeState *s, uint16_t a) { return (int8_t)s->data[a]; }
static uint16_t g_u2(BqeState *s, uint16_t a) { return (uint16_t)(s->data[a] | s->data[a + 1] << 8); }
static int16_t g_i2(BqeState *s, uint16_t a) { return (int16_t)g_u2(s, a); }
static void d_i2(BqeState *s, uint8_t r, long v) {
    if (v > 32767) v = 32767;
    if (v < -32768) v = -32768;
    s->direct[r] = (uint8_t)(v & 0xFF); s->direct[r + 1] = (uint8_t)((v >> 8) & 0xFF);
}

static void load_otp(BqeState *s) {
    static const uint8_t pins[9] = { 7, 7, 0, 7, 0, 7, 7, 7, 7 };
    memset(s->data, 0, sizeof s->data);
    dm_u1(s, BQ769X2_SET_CONF_DA, 0x06);
    dm_u2(s, BQ769X2_SET_CONF_VCELL_MODE, 0x1FFFu);
    dm_u1(s, BQ769X2_SET_PROT_ENABLED_A, 0xBC);
    dm_u1(s, BQ769X2_SET_PROT_ENABLED_B, 0x33);
    dm_u2(s, BQ769X2_SET_MFG_STATUS_INIT, 0x0010);
    dm_u1(s, BQ769X2_PROT_COV_THRESHOLD, 84);
    dm_u1(s, BQ769X2_PROT_COV_RECOV_HYST, 2);
    dm_u2(s, BQ769X2_PROT_COV_DELAY, 74);
    dm_u1(s, BQ769X2_PROT_CUV_THRESHOLD, 53);
    dm_u1(s, BQ769X2_PROT_CUV_RECOV_HYST, 2);
    dm_u2(s, BQ769X2_PROT_CUV_DELAY, 74);
    dm_u1(s, BQ769X2_PROT_OCC_THRESHOLD, 7);
    dm_u1(s, BQ769X2_PROT_OCC_DELAY, 4);
    dm_u2(s, BQ769X2_PROT_OCC_RECOVERY, (uint16_t)(int16_t)-200);
    dm_u1(s, BQ769X2_PROT_OCD1_THRESHOLD, 28);
    dm_u1(s, BQ769X2_PROT_OCD1_DELAY, 127);
    dm_u2(s, BQ769X2_PROT_OCD_RECOV_THRESHOLD, 200);
    dm_u1(s, BQ769X2_PROT_SCD_THRESHOLD, 5);
    dm_u1(s, BQ769X2_PROT_SCD_DELAY, 2);
    dm_u1(s, BQ769X2_PROT_SCD_RECOV_TIME, 5);
    dm_u1(s, BQ769X2_PROT_OTC_THRESHOLD, (uint8_t)(int8_t)45);
    dm_u1(s, BQ769X2_PROT_OTC_RECOVERY, (uint8_t)(int8_t)40);
    dm_u1(s, BQ769X2_PROT_OTD_THRESHOLD, (uint8_t)(int8_t)60);
    dm_u1(s, BQ769X2_PROT_OTD_RECOVERY, (uint8_t)(int8_t)55);
    dm_u1(s, BQ769X2_PROT_UTC_THRESHOLD, (uint8_t)(int8_t)0);
    dm_u1(s, BQ769X2_PROT_UTC_RECOVERY, (uint8_t)(int8_t)5);
    dm_u1(s, BQ769X2_PROT_UTD_THRESHOLD, (uint8_t)(int8_t)-10);
    dm_u1(s, BQ769X2_PROT_UTD_RECOVERY, (uint8_t)(int8_t)-5);
    dm_u1(s, BQ769X2_PROT_OTC_DELAY, 2);
    dm_u1(s, BQ769X2_PROT_OTD_DELAY, 2);
    dm_u1(s, BQ769X2_PROT_UTC_DELAY, 2);
    dm_u1(s, BQ769X2_PROT_UTD_DELAY, 2);
    dm_u1(s, BQ769X2_PROT_RECOVERY_TIME, 3);
    for (int i = 0; i < 9; i++) dm_u1(s, BQ769X2_SET_CONF_CFETOFF + i, pins[i]);
}

void bqe_init_instance(BqeState *s) {
    if (!s) return;
    memset(s, 0, sizeof *s);
    load_otp(s);
    s->mfg_status = g_u2(s, BQ769X2_SET_MFG_STATUS_INIT);
    s->alarm_latched = 0x0600;                         /* INITSTART | INITCOMP after power-on */
    s->shuntOhms = 0.001;
    s->i2cAddress = 0x08;
}

BqeState *bqe_create(void) { BqeState *s = (BqeState *)malloc(sizeof *s); if (s) bqe_init_instance(s); return s; }
void bqe_destroy(BqeState *s) { free(s); }
void bqe_init(void) { bqe_init_instance(&legacyState); }

void bqe_configure_instance(BqeState *s, const BqeConfig *c) {
    if (!s || !c) return;
    dm_u1(s, BQ769X2_SET_CONF_DA, c->daConfig);
    s->i2cAddress = c->i2cAddress;
    dm_u2(s, BQ769X2_SET_CONF_VCELL_MODE, c->usedCells);
    dm_u1(s, BQ769X2_SET_PROT_ENABLED_A, c->protEnabledA);
    dm_u1(s, BQ769X2_SET_PROT_ENABLED_B, c->protEnabledB);
    dm_u2(s, BQ769X2_SET_MFG_STATUS_INIT, c->mfgStatusInit);
    dm_u1(s, BQ769X2_PROT_COV_THRESHOLD, c->covThreshold); dm_u1(s, BQ769X2_PROT_COV_RECOV_HYST, c->covHyst); dm_u2(s, BQ769X2_PROT_COV_DELAY, c->covDelay);
    dm_u1(s, BQ769X2_PROT_CUV_THRESHOLD, c->cuvThreshold); dm_u1(s, BQ769X2_PROT_CUV_RECOV_HYST, c->cuvHyst); dm_u2(s, BQ769X2_PROT_CUV_DELAY, c->cuvDelay);
    dm_u1(s, BQ769X2_PROT_OCC_THRESHOLD, c->occThreshold); dm_u1(s, BQ769X2_PROT_OCC_DELAY, c->occDelay); dm_u2(s, BQ769X2_PROT_OCC_RECOVERY, (uint16_t)c->occRecoveryMilliAmps);
    dm_u1(s, BQ769X2_PROT_OCD1_THRESHOLD, c->ocd1Threshold); dm_u1(s, BQ769X2_PROT_OCD1_DELAY, c->ocd1Delay); dm_u2(s, BQ769X2_PROT_OCD_RECOV_THRESHOLD, c->ocdRecoveryMilliAmps);
    dm_u1(s, BQ769X2_PROT_SCD_THRESHOLD, c->scdThreshold); dm_u1(s, BQ769X2_PROT_SCD_DELAY, c->scdDelay); dm_u1(s, BQ769X2_PROT_SCD_RECOV_TIME, c->scdRecoverySeconds);
    dm_u1(s, BQ769X2_PROT_OTC_THRESHOLD, (uint8_t)c->otcThreshold); dm_u1(s, BQ769X2_PROT_OTC_RECOVERY, (uint8_t)c->otcRecovery);
    dm_u1(s, BQ769X2_PROT_OTD_THRESHOLD, (uint8_t)c->otdThreshold); dm_u1(s, BQ769X2_PROT_OTD_RECOVERY, (uint8_t)c->otdRecovery);
    dm_u1(s, BQ769X2_PROT_UTC_THRESHOLD, (uint8_t)c->utcThreshold); dm_u1(s, BQ769X2_PROT_UTC_RECOVERY, (uint8_t)c->utcRecovery);
    dm_u1(s, BQ769X2_PROT_UTD_THRESHOLD, (uint8_t)c->utdThreshold); dm_u1(s, BQ769X2_PROT_UTD_RECOVERY, (uint8_t)c->utdRecovery);
    dm_u1(s, BQ769X2_PROT_OTC_DELAY, c->otUtDelaySeconds); dm_u1(s, BQ769X2_PROT_OTD_DELAY, c->otUtDelaySeconds);
    dm_u1(s, BQ769X2_PROT_UTC_DELAY, c->otUtDelaySeconds); dm_u1(s, BQ769X2_PROT_UTD_DELAY, c->otUtDelaySeconds);
    dm_u1(s, BQ769X2_PROT_RECOVERY_TIME, c->recoveryTimeSeconds);
    for (int i = 0; i < 9; ++i) dm_u1(s, BQ769X2_SET_CONF_CFETOFF + i, c->pinConfig[i]);
    s->mfg_status = c->mfgStatusInit;
    s->shuntOhms = c->shuntMicroOhms * 1e-6;
}

static void update_battery_status(BqeState *s) {             /* Battery Status reflects mode changes at once */
    uint16_t bs = (uint16_t)(s->cfgupdate ? 0x0001 : 0) | (uint16_t)((s->ssA | s->ssB) ? 0x0800 : 0);
    s->direct[BQ769X2_CMD_BATTERY_STATUS] = bs & 0xFF;  s->direct[BQ769X2_CMD_BATTERY_STATUS + 1] = bs >> 8;
}

/* ---------- subcommands ---------- */
static void respond(BqeState *s, uint16_t addr, const uint8_t *bytes, uint8_t n) {
    memcpy(&s->data[addr], bytes, n);
}
static void subcmd_cmd(BqeState *s, uint16_t sc) {                 /* command-only subcommands */
    switch (sc) {
    case BQ769X2_SUBCMD_SET_CFGUPDATE: s->cfgupdate = 1; break;
    case BQ769X2_SUBCMD_EXIT_CFGUPDATE: s->cfgupdate = 0; break;
    case BQ769X2_SUBCMD_FET_ENABLE: s->mfg_status ^= 0x0010; break;
    case BQ769X2_SUBCMD_ALL_FETS_OFF: s->fets_off = 1; break;
    case BQ769X2_SUBCMD_ALL_FETS_ON: s->fets_off = 0; break;
    case BQ769X2_SUBCMD_RESET: bqe_init_instance(s); break;
    default: break;                                   /* SLEEP_DISABLE etc.: accepted, no effect */
    }
    update_battery_status(s);
}
static uint8_t resp_len(uint16_t sc) {                /* bytes returned by a subcommand read */
    switch (sc) {
    case BQ769X2_SUBCMD_DEVICE_NUMBER: case BQ769X2_SUBCMD_MFG_STATUS:
    case BQ769X2_SUBCMD_CB_ACTIVE_CELLS: return 2;
    case BQ769X2_SUBCMD_FW_VERSION: return 6;
    default: return 4;                                /* data memory: as Libre Solar's emulator */
    }
}
static void prepare_read(BqeState *s, uint16_t sc) {               /* fill the response for subcommand sc */
    uint8_t b[6];
    if (sc == BQ769X2_SUBCMD_DEVICE_NUMBER) { b[0] = 0x95; b[1] = 0x76; respond(s, sc, b, 2); }  /* 0x7695 */
    else if (sc == BQ769X2_SUBCMD_FW_VERSION) { memset(b, 0, 6); b[0] = 0x76; b[1] = 0x95; respond(s, sc, b, 6); }
    else if (sc == BQ769X2_SUBCMD_MFG_STATUS) { b[0] = s->mfg_status & 0xFF; b[1] = s->mfg_status >> 8; respond(s, sc, b, 2); }
    else if (sc == BQ769X2_SUBCMD_CB_ACTIVE_CELLS) { b[0] = s->cb_active & 0xFF; b[1] = s->cb_active >> 8; respond(s, sc, b, 2); }
}

void bqe_i2c_write_instance(BqeState *s, uint8_t reg, const uint8_t *d, uint8_t n) {
    if (!s) return;
    if (reg >= DIRECT_SIZE || reg + n > DIRECT_SIZE) return;
    if (reg == BQ769X2_CMD_ALARM_STATUS) {             /* write 1s to clear latched alarm bits */
        uint16_t m = d[0] | (n > 1 ? d[1] << 8 : 0);
        s->alarm_latched &= (uint16_t)~m;
        return;
    }
    memcpy(&s->direct[reg], d, n);
    uint16_t sc = (uint16_t)(s->direct[BQ769X2_CMD_SUBCMD_UPPER] << 8 | s->direct[BQ769X2_CMD_SUBCMD_LOWER]);
    if (reg == BQ769X2_SUBCMD_DATA_CHECKSUM && n >= 2) {
        /* checksum + length written: execute a write with data (data memory or subcommand) */
        uint8_t len = s->direct[BQ769X2_SUBCMD_DATA_LENGTH];
        if (len < BQ769X2_SUBCMD_OVERHEAD_BYTES || len - BQ769X2_SUBCMD_OVERHEAD_BYTES > 32) return;
        uint8_t nd = len - BQ769X2_SUBCMD_OVERHEAD_BYTES;
        uint8_t cs = s->direct[BQ769X2_CMD_SUBCMD_LOWER] + s->direct[BQ769X2_CMD_SUBCMD_UPPER];
        for (int i = 0; i < nd; i++) cs += s->direct[BQ769X2_SUBCMD_DATA_START + i];
        if ((uint8_t)~cs != s->direct[BQ769X2_SUBCMD_DATA_CHECKSUM]) return;   /* chip ignores bad checksum */
        if (BQ769X2_IS_DATA_MEM_REG_ADDR(sc)) {
            if (!s->cfgupdate) return;                 /* data memory writable only in CONFIG_UPDATE */
            memcpy(&s->data[sc], &s->direct[BQ769X2_SUBCMD_DATA_START], nd);
        } else if (sc == BQ769X2_SUBCMD_CB_ACTIVE_CELLS && nd >= 2) {
            s->cb_active = s->direct[BQ769X2_SUBCMD_DATA_START] | s->direct[BQ769X2_SUBCMD_DATA_START + 1] << 8;
        }
        return;
    }
    if (reg == BQ769X2_CMD_SUBCMD_LOWER && n == 2) {
        /* subcommand / data memory address written: execute (command-only) and prepare a read */
        if (!BQ769X2_IS_DATA_MEM_REG_ADDR(sc)) { subcmd_cmd(s, sc); prepare_read(s, sc); }
        if (sc >= DATA_SIZE) return;
        uint8_t nd = resp_len(sc);
        memcpy(&s->direct[BQ769X2_SUBCMD_DATA_START], &s->data[sc], nd);
        uint8_t cs = s->direct[BQ769X2_CMD_SUBCMD_LOWER] + s->direct[BQ769X2_CMD_SUBCMD_UPPER];
        for (int i = 0; i < nd; i++) cs += s->direct[BQ769X2_SUBCMD_DATA_START + i];
        s->direct[BQ769X2_SUBCMD_DATA_CHECKSUM] = (uint8_t)~cs;
        s->direct[BQ769X2_SUBCMD_DATA_LENGTH] = nd + BQ769X2_SUBCMD_OVERHEAD_BYTES;
    }
}

void bqe_i2c_read_instance(BqeState *s, uint8_t reg, uint8_t *d, uint8_t n) {
    if (!s) { memset(d, 0, n); return; }
    for (int i = 0; i < n; i++) d[i] = (reg + i < DIRECT_SIZE) ? s->direct[reg + i] : 0;
}

void bqe_i2c_transaction_instance(BqeState *s, const uint8_t *q, uint8_t *r) {
    if (!s || !q || !r) return;
    uint32_t seq=(uint32_t)q[0]|((uint32_t)q[1]<<8)|((uint32_t)q[2]<<16)|((uint32_t)q[3]<<24);
    if (seq==0 || (s->i2cTxnSeen && seq==s->lastI2cTxn)) {
        memcpy(r,s->i2cResponse,BQE_I2C_RESP_BYTES); return;
    }
    s->lastI2cTxn=seq; s->i2cTxnSeen=1;
    memset(r,0,BQE_I2C_RESP_BYTES);
    r[0]=q[0]; r[1]=q[1]; r[2]=q[2]; r[3]=q[3];
    uint8_t addr=q[4], read=q[5], reg=q[6], n=q[7];
    if (addr!=s->i2cAddress || addr>0x7F || read>1 || n==0 || n>32 ||
        (unsigned)reg+(unsigned)n>DIRECT_SIZE) { r[4]=1; memcpy(s->i2cResponse,r,BQE_I2C_RESP_BYTES); return; }
    if (read) bqe_i2c_read_instance(s,reg,&r[6],n);
    else bqe_i2c_write_instance(s,reg,&q[8],n);
    r[4]=0; r[5]=n; memcpy(s->i2cResponse,r,BQE_I2C_RESP_BYTES);
}

void bqe_i2c_write(uint8_t reg, const uint8_t *d, uint8_t n) { bqe_i2c_write_instance(&legacyState, reg, d, n); }
void bqe_i2c_read(uint8_t reg, uint8_t *d, uint8_t n) { bqe_i2c_read_instance(&legacyState, reg, d, n); }

/* ---------- protections ---------- */
/* fault set after the condition persists for 'delay'; cleared after 'rec' persists for 'trec' */
static int prot(BqeState *s, int p, int enabled, int cond, double delay, int rec, double trec, double dt,
                uint8_t *ss, uint8_t *sa, uint8_t bit) {
    int fault = (*ss & bit) != 0;
    if (!enabled) { *ss &= (uint8_t)~bit; *sa &= (uint8_t)~bit; s->tAlert[p] = s->tRec[p] = 0; return 0; }
    if (!fault) {
        if (cond) { *sa |= bit; s->tAlert[p] += dt; } else { *sa &= (uint8_t)~bit; s->tAlert[p] = 0; }
        if (s->tAlert[p] >= delay - 1e-9) { *ss |= bit; *sa &= (uint8_t)~bit; s->tAlert[p] = 0; s->tRec[p] = 0; }
    } else {
        s->tRec[p] = rec ? s->tRec[p] + dt : 0;
        if (s->tRec[p] >= trec - 1e-9) { *ss &= (uint8_t)~bit; s->tRec[p] = 0; }
    }
    return (*ss & bit) != 0;
}

void bqe_step_instance(BqeState *s, double dt, const double *vIn, double iChg, const double *tPinK, double tIntK,
              double vPack, double vLd, double loadRemoved, const uint8_t *wr, uint8_t *snap,
              uint8_t *fet) {
    if (!s) return;
    s->t += dt;  s->seq++;
    /* host write (one per step) */
    uint32_t ws = (uint32_t)wr[0] | (uint32_t)wr[1] << 8 | (uint32_t)wr[2] << 16 | (uint32_t)wr[3] << 24;
    if (ws != 0 && ws != s->lastWr) {
        uint8_t n = wr[5] > 32 ? 32 : wr[5];
        bqe_i2c_write_instance(s, wr[4], wr + 6, n);
        s->lastWr = ws;  s->ack = ws;
    }

    /* ---- measurements (as the ADC reports them) ---- */
    uint16_t used = g_u2(s, BQ769X2_SET_CONF_VCELL_MODE);
    uint8_t da = g_u1(s, BQ769X2_SET_CONF_DA);
    double ampsLsb = (da & 0x03) == 0 ? 1e-4 : (da & 0x03) == 1 ? 1e-3 : (da & 0x03) == 2 ? 1e-2 : 1e-1;
    double voltLsb = (da & 0x04) ? 0.01 : 0.001;  /* stack / PACK / LD: centivolts or mV */
    double vStack = 0, vMax = -1, vMin = 1e9;
    for (int c = 0; c < 16; c++) {
        d_i2(s, BQ769X2_CMD_VOLTAGE_CELL_1 + 2 * c, lround(vIn[c] * 1000.0));
        vStack += vIn[c];
        if (used & (1u << c)) { if (vIn[c] > vMax) vMax = vIn[c]; if (vIn[c] < vMin) vMin = vIn[c]; }
    }
    d_i2(s, BQ769X2_CMD_VOLTAGE_STACK, lround(vStack / voltLsb));
    d_i2(s, BQ769X2_CMD_VOLTAGE_PACK, lround(vPack / voltLsb));
    d_i2(s, BQ769X2_CMD_VOLTAGE_LD, lround(vLd / voltLsb));
    d_i2(s, BQ769X2_CMD_CURRENT_CC2, lround(iChg / ampsLsb));
    d_i2(s, BQ769X2_CMD_TEMP_INT, lround(tIntK * 10.0));
    double tMax = -1e9, tMin = 1e9;
    for (int p = 0; p < 9; p++) {
        d_i2(s, BQ769X2_CMD_TEMP_CFETOFF + 2 * p, lround(tPinK[p] * 10.0));
        uint8_t cfg = g_u1(s, BQ769X2_SET_CONF_CFETOFF + p);
        if ((cfg & 0x03) == 0x03 && ((cfg >> 4) & 0x03) == 0) {      /* thermistor, cell temp */
            double tc = tPinK[p] - 273.15;
            if (tc > tMax) tMax = tc;
            if (tc < tMin) tMin = tc;
        }
    }
    if (tMax < -1e8) { tMax = tIntK - 273.15; tMin = tMax; }

    /* ---- protections (suspended in CONFIG_UPDATE, as the chip) ---- */
    uint8_t enA = g_u1(s, BQ769X2_SET_PROT_ENABLED_A), enB = g_u1(s, BQ769X2_SET_PROT_ENABLED_B);
    double rec = g_u1(s, BQ769X2_PROT_RECOVERY_TIME);
    double rShunt = s->shuntOhms;
    if (!s->cfgupdate) {
        double cov = g_u1(s, BQ769X2_PROT_COV_THRESHOLD) * 0.0506, covH = g_u1(s, BQ769X2_PROT_COV_RECOV_HYST) * 0.0506;
        double cuv = g_u1(s, BQ769X2_PROT_CUV_THRESHOLD) * 0.0506, cuvH = g_u1(s, BQ769X2_PROT_CUV_RECOV_HYST) * 0.0506;
        prot(s, P_COV, enA & 0x08, vMax >= cov, g_u2(s, BQ769X2_PROT_COV_DELAY) * 3.3e-3, vMax < cov - covH, rec, dt, &s->ssA, &s->saA, 0x08);
        prot(s, P_CUV, enA & 0x04, vMin <= cuv, g_u2(s, BQ769X2_PROT_CUV_DELAY) * 3.3e-3, vMin > cuv + cuvH, rec, dt, &s->ssA, &s->saA, 0x04);
        double occ = g_u1(s, BQ769X2_PROT_OCC_THRESHOLD) * 2e-3 / rShunt;
        double occRec = g_i2(s, BQ769X2_PROT_OCC_RECOVERY) * 1e-3;
        prot(s, P_OCC, enA & 0x10, iChg >= occ, 6.6e-3 + g_u1(s, BQ769X2_PROT_OCC_DELAY) * 3.3e-3, iChg <= occRec, rec, dt, &s->ssA, &s->saA, 0x10);
        double ocd = g_u1(s, BQ769X2_PROT_OCD1_THRESHOLD) * 2e-3 / rShunt;
        double ocdRec = g_i2(s, BQ769X2_PROT_OCD_RECOV_THRESHOLD) * 1e-3;
        /* OCD recovery: charge current above the recovery threshold, or load removed */
        prot(s, P_OCD1, enA & 0x20, -iChg >= ocd, 6.6e-3 + g_u1(s, BQ769X2_PROT_OCD1_DELAY) * 3.3e-3,
             iChg >= ocdRec || loadRemoved > 0.5, rec, dt, &s->ssA, &s->saA, 0x20);
        static const uint16_t scdTab[] = { 10, 20, 40, 60, 80, 100, 125, 150, 175, 200, 250, 300, 350, 400, 450, 500 };
        uint8_t si = g_u1(s, BQ769X2_PROT_SCD_THRESHOLD) & 0x0F;
        double scd = scdTab[si] * 1e-3 / rShunt;
        double scdDelay = (g_u1(s, BQ769X2_PROT_SCD_DELAY) > 0 ? g_u1(s, BQ769X2_PROT_SCD_DELAY) - 1 : 0) * 15e-6;
        prot(s, P_SCD, enA & 0x80, -iChg >= scd, scdDelay, 1, g_u1(s, BQ769X2_PROT_SCD_RECOV_TIME), dt, &s->ssA, &s->saA, 0x80);
        prot(s, P_OTC, enB & 0x10, tMax >= g_i1(s, BQ769X2_PROT_OTC_THRESHOLD), g_u1(s, BQ769X2_PROT_OTC_DELAY),
             tMax <= g_i1(s, BQ769X2_PROT_OTC_RECOVERY), rec, dt, &s->ssB, &s->saB, 0x10);
        prot(s, P_OTD, enB & 0x20, tMax >= g_i1(s, BQ769X2_PROT_OTD_THRESHOLD), g_u1(s, BQ769X2_PROT_OTD_DELAY),
             tMax <= g_i1(s, BQ769X2_PROT_OTD_RECOVERY), rec, dt, &s->ssB, &s->saB, 0x20);
        prot(s, P_UTC, enB & 0x01, tMin <= g_i1(s, BQ769X2_PROT_UTC_THRESHOLD), g_u1(s, BQ769X2_PROT_UTC_DELAY),
             tMin >= g_i1(s, BQ769X2_PROT_UTC_RECOVERY), rec, dt, &s->ssB, &s->saB, 0x01);
        prot(s, P_UTD, enB & 0x02, tMin <= g_i1(s, BQ769X2_PROT_UTD_THRESHOLD), g_u1(s, BQ769X2_PROT_UTD_DELAY),
             tMin >= g_i1(s, BQ769X2_PROT_UTD_RECOVERY), rec, dt, &s->ssB, &s->saB, 0x02);
    }

    /* ---- autonomous FET control ---- */
    int fetEn = (s->mfg_status & 0x0010) != 0;
    int ok = fetEn && !s->cfgupdate && !s->fets_off;
    s->chg = (uint8_t)(ok && !(s->ssA & (0x08 | 0x10)) && !(s->ssB & (0x01 | 0x10 | 0x04 | 0x40)));
    s->dsg = (uint8_t)(ok && !(s->ssA & (0x04 | 0x20 | 0x40 | 0x80)) && !(s->ssB & (0x02 | 0x20 | 0x04 | 0x40)));

    /* ---- status registers ---- */
    s->direct[BQ769X2_CMD_SAFETY_ALERT_A] = s->saA;  s->direct[BQ769X2_CMD_SAFETY_STATUS_A] = s->ssA;
    s->direct[BQ769X2_CMD_SAFETY_ALERT_B] = s->saB;  s->direct[BQ769X2_CMD_SAFETY_STATUS_B] = s->ssB;
    s->direct[BQ769X2_CMD_SAFETY_ALERT_C] = 0;      s->direct[BQ769X2_CMD_SAFETY_STATUS_C] = 0;
    update_battery_status(s);
    s->direct[BQ769X2_CMD_FET_STATUS] = (uint8_t)(s->chg ? 0x01 : 0) | (uint8_t)(s->dsg ? 0x04 : 0);
    uint16_t raw = 0x0080 | 0x0002;                                   /* FULLSCAN | ADSCAN */
    if (s->saA || s->ssA) raw |= 0x4000;                                /* SSA */
    if (s->saB || s->ssB) raw |= 0x8000;                                /* SSBC */
    if (!s->chg) raw |= 0x0040;                                        /* XCHG */
    if (!s->dsg) raw |= 0x0020;                                        /* XDSG */
    s->alarm_latched |= raw;
    s->direct[BQ769X2_CMD_ALARM_STATUS] = s->alarm_latched & 0xFF;  s->direct[BQ769X2_CMD_ALARM_STATUS + 1] = s->alarm_latched >> 8;
    s->direct[BQ769X2_CMD_ALARM_RAW_STATUS] = raw & 0xFF;          s->direct[BQ769X2_CMD_ALARM_RAW_STATUS + 1] = raw >> 8;

    /* ---- snapshot ---- */
    uint32_t tms = (uint32_t)lround(s->t * 1000.0);
    snap[0] = 'B'; snap[1] = 'Q'; snap[2] = '7'; snap[3] = '6';
    for (int i = 0; i < 4; i++) { snap[4 + i] = (s->seq >> (8 * i)) & 0xFF; snap[8 + i] = (s->ack >> (8 * i)) & 0xFF; snap[12 + i] = (tms >> (8 * i)) & 0xFF; }
    memcpy(snap + 16, s->direct, DIRECT_SIZE);
    fet[0] = s->chg;  fet[1] = s->dsg;
}

void bqe_step(double dt, const double *vIn, double iChg, const double *tPinK, double tIntK,
              double vPack, double vLd, double loadRemoved, const uint8_t *wr, uint8_t *snap,
              uint8_t *fet) {
    bqe_step_instance(&legacyState, dt, vIn, iChg, tPinK, tIntK, vPack, vLd, loadRemoved, wr, snap, fet);
}
