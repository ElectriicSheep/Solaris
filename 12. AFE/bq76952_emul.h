/* bq76952_emul.h - behavioural emulator of the TI BQ76952 battery monitor / protector.
 *
 * Emulates the chip as a host sees it over I2C (direct commands, subcommands and data memory,
 * register map from Libre Solar bq769x2_registers.h) and its autonomous behaviour that matters
 * here: measurements, cell / current / temperature protections with delays and recovery, and
 * autonomous CHG / DSG FET control. Behaviour follows the BQ769x2 documentation as used by the
 * Libre Solar driver; it is NOT TI's firmware: validate against the BQ76952EVM.
 * Not emulated (v1): sleep / deep sleep / shutdown, cell balancing, precharge / predischarge,
 * OCD2, PF (permanent fail), CRC on I2C, OTP programming, LD-pin detection (approximated).
 *
 * Host link (SITL): the emulator publishes a snapshot of its direct-command memory each step;
 * the host applies one register write per step and sees the result in the next snapshot.
 */
#ifndef BQ76952_EMUL_H
#define BQ76952_EMUL_H
#include <stdint.h>

/* Opaque per-instance state. Each Simulink block owns one allocation. */
typedef struct BqeState BqeState;
typedef struct {
    uint16_t usedCells;
    uint32_t shuntMicroOhms;
    uint8_t i2cAddress;
    uint8_t daConfig, protEnabledA, protEnabledB;
    uint16_t mfgStatusInit;
    uint8_t covThreshold, covHyst; uint16_t covDelay;
    uint8_t cuvThreshold, cuvHyst; uint16_t cuvDelay;
    uint8_t occThreshold, occDelay; int16_t occRecoveryMilliAmps;
    uint8_t ocd1Threshold, ocd1Delay; uint16_t ocdRecoveryMilliAmps;
    uint8_t scdThreshold, scdDelay, scdRecoverySeconds;
    int8_t otcThreshold, otcRecovery, otdThreshold, otdRecovery;
    int8_t utcThreshold, utcRecovery, utdThreshold, utdRecovery;
    uint8_t otUtDelaySeconds, recoveryTimeSeconds;
    uint8_t pinConfig[9];
} BqeConfig;
BqeState *bqe_create(void);
void bqe_destroy(BqeState *state);
void bqe_init_instance(BqeState *state);
void bqe_configure_instance(BqeState *state, const BqeConfig *config);
void bqe_i2c_write_instance(BqeState *state, uint8_t reg, const uint8_t *data, uint8_t len);
void bqe_i2c_read_instance(BqeState *state, uint8_t reg, uint8_t *data, uint8_t len);
void bqe_step_instance(BqeState *state, double dt, const double *vIn, double iChg,
                       const double *tPinK, double tIntK, double vPack, double vLd,
                       double loadRemoved, const uint8_t *wr, uint8_t *snap, uint8_t *fet);

#define BQE_SNAP_BYTES  144   /* 'B''Q''7''6', seq u32, ack u32, t_ms u32, direct memory [128] */
#define BQE_WRITE_BYTES 40    /* seq u32 (0 = none), reg u8, len u8, data [32], pad [2] */
#define BQE_I2C_REQ_BYTES 40  /* seq u32, 7-bit address, read flag, register, length, data[32] */
#define BQE_I2C_RESP_BYTES 40 /* seq u32, status (0 ACK/1 NACK), length, data[32], pad */
void bqe_i2c_transaction_instance(BqeState *state, const uint8_t *request,
                                  uint8_t *response);

/* Power-on reset: registers cleared, data memory loaded from solaris_config.h (as OTP). */
void bqe_init(void);

/* One step of dt seconds.
 *  vIn[16]      voltage across each VC input (V); unused inputs 0
 *  iChg         pack current through the shunt, A, CHARGE POSITIVE (TI convention)
 *  tPinK[9]     temperature at each multi-function pin (K), order CFETOFF DFETOFF ALERT TS1 TS2
 *               TS3 HDQ DCHG DDSG; only pins configured as cell thermistors are used
 *  tIntK        die temperature (K)
 *  vPack, vLd   PACK and LD pin voltages (V)
 *  loadRemoved  1 if no load is connected (stands in for the LD-pin load-removal detection)
 *  wr[40]       host write packet (seq 0 = none); applied once per new seq
 *  snap[144]    out: snapshot for the host
 *  fet[2]       out: CHG FET on, DSG FET on
 */
void bqe_step(double dt, const double *vIn, double iChg, const double *tPinK, double tIntK,
              double vPack, double vLd, double loadRemoved, const uint8_t *wr, uint8_t *snap,
              uint8_t *fet);

/* Direct I2C access (native tools / unit tests): same semantics as the snapshot path. */
void bqe_i2c_write(uint8_t reg, const uint8_t *data, uint8_t len);
void bqe_i2c_read(uint8_t reg, uint8_t *data, uint8_t len);

#endif
