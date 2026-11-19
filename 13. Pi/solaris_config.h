/* solaris_config.h - BQ76952 configuration for the Solaris pack (13S7P Samsung INR18650-35E).
 *
 * One definition used by BOTH sides:
 *  - the emulator loads it at power-on, as if programmed into the chip's OTP (so the pack
 *    protects itself and switches its FETs with no host attached), and
 *  - the Pi host writes it into the real chip's RAM with --configure (needed on the BQ76952EVM,
 *    whose OTP is not programmed with these values).
 * Encodings follow the BQ769x2 data memory (as used by the Libre Solar driver, Apache-2.0):
 *   COV/CUV threshold: 50.6 mV units; hysteresis: 50.6 mV units; delay: 3.3 ms units
 *   OCC/OCD1 threshold: 2 mV across the shunt; delay: 6.6 ms + n x 3.3 ms
 *   SCD threshold: index into {10,20,40,60,80,100,125,150,175,200,250,300,350,400,450,500} mV
 *   SCD delay: (n - 1) x 15 us;  temperatures: degC (int8);  OT/UT delays: s
 * PLACEHOLDERS (engineering judgement, to confirm): limits from the 35E datasheet Ver 1.1 x 7P,
 * shunt 1 mOhm (as the EVM), all delays / recovery times at TI-style defaults.
 */
#ifndef SOLARIS_CONFIG_H
#define SOLARIS_CONFIG_H

#define SOL_N_GROUPS          13          /* series groups (7P each) */
#define SOL_USED_CELLS        0x1FFFu     /* VCell Mode: VC inputs 1-13 used (check board wiring) */
#define SOL_SHUNT_UOHM        1000u       /* sense resistor, uOhm */
#define SOL_I2C_ADDR          0x08        /* BQ76952 default 7-bit I2C address */

#define SOL_DA_CONFIG         0x06        /* user amps 10 mA; stack/pack/LD in 10 mV */
#define SOL_PROT_ENABLED_A    0xBC        /* CUV COV OCC OCD1 SCD */
#define SOL_PROT_ENABLED_B    0x33        /* UTC UTD OTC OTD */
#define SOL_MFG_STATUS_INIT   0x0010      /* FET_EN: autonomous FET control from power-up */

#define SOL_COV_THRESHOLD     84          /* 84 x 50.6 mV = 4.250 V (MSL) */
#define SOL_COV_HYST          2           /* recover below 4.149 V */
#define SOL_COV_DELAY         74          /* 74 x 3.3 ms = 244 ms */
#define SOL_CUV_THRESHOLD     53          /* 53 x 50.6 mV = 2.682 V (35E cut-off 2.65 V) */
#define SOL_CUV_HYST          2           /* recover above 2.783 V */
#define SOL_CUV_DELAY         74          /* 244 ms */
#define SOL_OCC_THRESHOLD     7           /* 14 mV / 1 mOhm = 14 A (7 x 2.0 A max charge) */
#define SOL_OCC_DELAY         4           /* 6.6 + 4 x 3.3 = 19.8 ms */
#define SOL_OCC_RECOVERY_MA   (-200)      /* recover once discharging >= 200 mA */
#define SOL_OCD1_THRESHOLD    28          /* 56 mV / 1 mOhm = 56 A (7 x 8 A max continuous) */
#define SOL_OCD1_DELAY        127         /* 6.6 + 127 x 3.3 = 426 ms (motor transients) */
#define SOL_SCD_THRESHOLD     5           /* 100 mV / 1 mOhm = 100 A */
#define SOL_SCD_DELAY         2           /* 15 us */
#define SOL_SCD_RECOV_TIME_S  5
#define SOL_OTC_THRESHOLD     45          /* degC, charge 0-45 degC */
#define SOL_OTC_RECOVERY      40
#define SOL_OTD_THRESHOLD     60          /* degC, discharge -10..60 degC */
#define SOL_OTD_RECOVERY      55
#define SOL_UTC_THRESHOLD     0
#define SOL_UTC_RECOVERY      5
#define SOL_UTD_THRESHOLD     (-10)
#define SOL_UTD_RECOVERY      (-5)
#define SOL_OT_UT_DELAY_S     2
#define SOL_RECOVERY_TIME_S   3

/* Multi-function pins (data memory 0x92FA..0x9302, order CFETOFF DFETOFF ALERT TS1 TS2 TS3
 * HDQ DCHG DDSG). 0x07 = thermistor, cell temperature. 7 cell thermistors (one per two groups
 * for groups 1-12, one on group 13); TS2 is the wake / power-button input, ALERT unused. */
#define SOL_PIN_THERM         0x07
#define SOL_PIN_UNUSED        0x00
#define SOL_PIN_CONFIG        { SOL_PIN_THERM, SOL_PIN_THERM, SOL_PIN_UNUSED, SOL_PIN_THERM, \
                                SOL_PIN_UNUSED, SOL_PIN_THERM, SOL_PIN_THERM, SOL_PIN_THERM, \
                                SOL_PIN_THERM }
/* thermistor k (0-6) -> pin index (0 CFETOFF .. 8 DDSG), and which groups it sits on */
#define SOL_N_THERM           7
#define SOL_THERM_PINS        { 3, 5, 6, 7, 8, 0, 1 }      /* TS1 TS3 HDQ DCHG DDSG CFETOFF DFETOFF */

#endif
