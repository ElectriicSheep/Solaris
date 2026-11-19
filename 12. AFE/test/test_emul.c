/* test_emul.c - checks the BQ76952 emulator.
 * Part 1 drives it through the unmodified Libre Solar bq769x2 interface layer (the host code
 * used with real chips): device number, MFG status, CONFIG_UPDATE, data memory write/read.
 * Part 2 checks measurements, protections (delay, FET action, recovery) and FET control. */
#include "bq76952_emul.h"
#include "solaris_config.h"
#include "bq769x2_interface.h"
#include "bq769x2_priv.h"
#include "bq769x2_registers.h"
#include <math.h>
#include <stdio.h>
#include <string.h>

int bq_log_level = 1;
void bq_usleep(int us) { (void)us; }
static int wr(const struct device *d, uint8_t r, const uint8_t *b, size_t n) { (void)d; bqe_i2c_write(r, b, (uint8_t)n); return 0; }
static int rd(const struct device *d, uint8_t r, uint8_t *b, size_t n) { (void)d; bqe_i2c_read(r, b, (uint8_t)n); return 0; }

static int fails = 0;
#define CHECK(c, ...) do { int _ok = (c); printf("  %s ", _ok ? "PASS" : "FAIL"); printf(__VA_ARGS__); printf("\n"); if (!_ok) fails++; } while (0)

static double vIn[16], tPin[9], iChg = 0, loadRem = 0;
static uint8_t snap[BQE_SNAP_BYTES], fet[2], noWr[BQE_WRITE_BYTES];
static void run(double seconds) { for (int k = 0; k < (int)lround(seconds / 0.01); k++) bqe_step(0.01, vIn, iChg, tPin, 298.15, 48, 48, loadRem, noWr, snap, fet); }
static void nominal(void) { for (int c = 0; c < 16; c++) vIn[c] = c < 13 ? 3.7 : 0; for (int p = 0; p < 9; p++) tPin[p] = 298.15; iChg = 0; loadRem = 0; }
static int16_t reg_i2(uint8_t r) { return (int16_t)(snap[16 + r] | snap[17 + r] << 8); }
/* time until the FET changes, s (cap) */
static double until(int which, int want, double cap) { double t = 0; while (t < cap) { run(0.01); t += 0.01; if (fet[which] == want) return t; } return -1; }

int main(void) {
    struct bms_ic_bq769x2_config cfg; memset(&cfg, 0, sizeof cfg); cfg.read_bytes = rd; cfg.write_bytes = wr;
    struct bms_ic_bq769x2_data data; memset(&data, 0, sizeof data);
    struct device dev = { "bq", &cfg, &data };

    printf("1. host protocol via the Libre Solar interface layer\n");
    bqe_init(); nominal(); run(0.05);
    uint16_t u2 = 0; uint8_t u1 = 0;
    CHECK(bq769x2_subcmd_read_u2(&dev, BQ769X2_SUBCMD_DEVICE_NUMBER, &u2) == 0 && u2 == 0x7695, "DEVICE_NUMBER = 0x%04X", u2);
    CHECK(bq769x2_subcmd_read_u2(&dev, BQ769X2_SUBCMD_MFG_STATUS, &u2) == 0 && (u2 & 0x10), "MFG_STATUS FET_EN set (0x%04X)", u2);
    CHECK(bq769x2_datamem_read_u1(&dev, BQ769X2_PROT_COV_THRESHOLD, &u1) == 0 && u1 == SOL_COV_THRESHOLD, "COV threshold from OTP = %u", u1);
    CHECK(bq769x2_datamem_write_u1(&dev, BQ769X2_PROT_COV_THRESHOLD, 80) == 0 && bq769x2_datamem_read_u1(&dev, BQ769X2_PROT_COV_THRESHOLD, &u1) == 0 && u1 == SOL_COV_THRESHOLD,
          "data memory write outside CONFIG_UPDATE ignored (still %u)", u1);
    run(0.01);
    CHECK(bq769x2_config_update_mode(&dev, true) == 0, "enter CONFIG_UPDATE");
    run(0.01);
    CHECK(fet[0] == 0 && fet[1] == 0, "FETs off in CONFIG_UPDATE");
    CHECK(bq769x2_datamem_write_u1(&dev, BQ769X2_PROT_COV_THRESHOLD, 80) == 0 && bq769x2_datamem_read_u1(&dev, BQ769X2_PROT_COV_THRESHOLD, &u1) == 0 && u1 == 80,
          "data memory write in CONFIG_UPDATE (now %u)", u1);
    int16_t i2 = 0;
    CHECK(bq769x2_datamem_write_i2(&dev, BQ769X2_PROT_OCC_RECOVERY, -300) == 0 && bq769x2_datamem_read_u2(&dev, BQ769X2_PROT_OCC_RECOVERY, &u2) == 0 && (int16_t)u2 == -300,
          "signed 2-byte data memory round trip (%d)", (int16_t)u2);
    CHECK(bq769x2_config_update_mode(&dev, false) == 0, "exit CONFIG_UPDATE");
    run(0.01);
    CHECK(fet[0] && fet[1], "FETs back on");
    (void)i2;

    printf("2. measurements (DA config 0x06: 10 mA, 10 mV stack)\n");
    bqe_init(); nominal(); vIn[4] = 3.6543; iChg = -12.345; tPin[3] = 303.15; run(0.02);
    CHECK(reg_i2(BQ769X2_CMD_VOLTAGE_CELL_1 + 8) == 3654, "cell 5 = %d mV", reg_i2(BQ769X2_CMD_VOLTAGE_CELL_1 + 8));
    CHECK(reg_i2(BQ769X2_CMD_VOLTAGE_STACK) == 4805, "stack = %d x 10 mV (12 x 3.7 + 3.654 V)", reg_i2(BQ769X2_CMD_VOLTAGE_STACK));
    CHECK(reg_i2(BQ769X2_CMD_CURRENT_CC2) == -1235 || reg_i2(BQ769X2_CMD_CURRENT_CC2) == -1234, "CC2 = %d x 10 mA (charge positive)", reg_i2(BQ769X2_CMD_CURRENT_CC2));
    CHECK(reg_i2(BQ769X2_CMD_TEMP_TS1) == 3032, "TS1 = %d x 0.1 K", reg_i2(BQ769X2_CMD_TEMP_TS1));
    CHECK(fet[0] && fet[1], "both FETs on at power-up with no faults (autonomous, no host)");

    printf("3. protections\n");
    double t;
    bqe_init(); nominal(); run(0.05); vIn[4] = 4.30;
    t = until(0, 0, 2); CHECK(t > 0.23 && t < 0.27 && fet[1], "COV: CHG off after %.2f s (delay 0.244 s), DSG stays on", t);
    vIn[4] = 4.10; t = until(0, 1, 10); CHECK(t > 2.95 && t < 3.1, "COV recovers %.2f s after cell < 4.149 V (recovery 3 s)", t);
    bqe_init(); nominal(); run(0.05); vIn[0] = 2.60;
    t = until(1, 0, 2); CHECK(t > 0.23 && t < 0.27 && fet[0], "CUV: DSG off after %.2f s, CHG stays on", t);
    bqe_init(); nominal(); run(0.05); iChg = 15;
    t = until(0, 0, 1); CHECK(t > 0.015 && t < 0.035, "OCC (15 A > 14 A): CHG off after %.3f s (delay 19.8 ms)", t);
    iChg = 0; run(5); CHECK(!fet[0], "OCC stays latched with no discharge");
    iChg = -1; t = until(0, 1, 5); CHECK(t > 2.95 && t < 3.1, "OCC recovers %.2f s into a 1 A discharge", t);
    bqe_init(); nominal(); run(0.05); iChg = -60;
    t = until(1, 0, 2); CHECK(t > 0.42 && t < 0.44, "OCD1 (60 A > 56 A): DSG off after %.2f s (delay 0.426 s)", t);
    iChg = 0; run(5); CHECK(!fet[1], "OCD1 stays latched while the load is connected");
    loadRem = 1; t = until(1, 1, 5); CHECK(t > 2.95 && t < 3.1, "OCD1 recovers %.2f s after load removal", t);
    bqe_init(); nominal(); run(0.05); iChg = -120;
    t = until(1, 0, 1); CHECK(t > 0 && t <= 0.011, "SCD (120 A > 100 A): DSG off in %.3f s (one step)", t);
    iChg = 0; t = until(1, 1, 10); CHECK(t > 4.95 && t < 5.1, "SCD recovers after %.2f s (5 s)", t);
    bqe_init(); nominal(); run(0.05); tPin[3] = 273.15 + 46;
    t = until(0, 0, 5); CHECK(t > 1.95 && t < 2.05 && fet[1], "OTC (46 degC on TS1): CHG off after %.2f s, DSG on", t);
    tPin[3] = 273.15 + 61; t = until(1, 0, 5); CHECK(t > 1.95 && t < 2.05, "OTD (61 degC): DSG off after %.2f s", t);
    tPin[3] = 273.15 + 39; t = until(1, 1, 10); CHECK(t > 2.9 && fet[0], "OT recovered (39 degC) after %.2f s", t);
    bqe_init(); nominal(); run(0.05); tPin[4] = 273.15 + 80; run(3);
    CHECK(fet[0] && fet[1], "TS2 (wake pin, not a thermistor) ignored at 80 degC");
    bqe_init(); nominal(); run(0.05); tPin[0] = 273.15 - 12;
    t = until(1, 0, 5); CHECK(t > 1.95 && !fet[0], "UTD (-12 degC on CFETOFF thermistor): DSG off after %.2f s (CHG already off by UTC)", t);

    printf("4. host commands\n");
    bqe_init(); nominal(); run(0.05);
    bq769x2_subcmd_cmd_only(&dev, BQ769X2_SUBCMD_ALL_FETS_OFF); run(0.02); CHECK(!fet[0] && !fet[1], "ALL_FETS_OFF");
    bq769x2_subcmd_cmd_only(&dev, BQ769X2_SUBCMD_ALL_FETS_ON); run(0.02); CHECK(fet[0] && fet[1], "ALL_FETS_ON");
    bq769x2_subcmd_cmd_only(&dev, BQ769X2_SUBCMD_FET_ENABLE); run(0.02); CHECK(!fet[0] && !fet[1], "FET_ENABLE toggles FET_EN off: FET test mode, FETs off");
    uint8_t clr[2] = { 0xFF, 0xFF }; uint8_t a[2];
    vIn[4] = 4.3; run(0.5); vIn[4] = 3.7; run(0.01);
    bqe_i2c_read(BQ769X2_CMD_ALARM_STATUS, a, 2); int had = (a[1] & 0x40) != 0;
    bqe_i2c_write(BQ769X2_CMD_ALARM_STATUS, clr, 2); bqe_i2c_read(BQ769X2_CMD_ALARM_STATUS, a, 2);
    CHECK(had && !(a[1] & 0x80), "alarm status latched SSA and cleared by writing 1s (0x%02X%02X)", a[1], a[0]);

    printf("\n%s (%d failed)\n", fails ? "FAIL" : "PASS", fails);
    return fails != 0;
}
