# 12. AFE - BQ76952 emulator

`bq76952_emul.c` emulates the TI BQ76952 as a host sees it over I2C, and its autonomous
behaviour, for software-in-the-loop (SITL) tests of the Pi with the Simulink plant.

**What it is:** a behavioural model built from the BQ769x2 documentation as used by the Libre
Solar driver (register map and subcommand protocol from Libre Solar `bms-firmware`, Apache-2.0).
It is not TI's firmware: thresholds, delays, recovery and register contents follow the documented
behaviour; timing is resolved to the 10 ms step. Validate against the BQ76952EVM before relying on
fine details.

**Emulated:** cell voltages (16 inputs, VCell Mode 13 used), stack / PACK / LD voltage, CC2 current
(user units from DA Config), 9 multi-function pin temperatures; Safety Alert / Status A and B;
CUV, COV, OCC, OCD1, SCD, OTC, OTD, UTC, UTD with their thresholds, delays and recovery; autonomous
CHG / DSG FET control (FET_EN); Battery Status, Alarm Status (latched, write-1-to-clear), FET Status;
subcommands DEVICE_NUMBER, FW_VERSION, MFG_STATUS, FET_ENABLE, ALL_FETS_OFF / ON, RESET,
SET / EXIT_CFGUPDATE, CB_ACTIVE_CELLS; data memory read / write with checksum (writes only in
CONFIG_UPDATE). At power-on it loads `13. Pi/solaris_config.h` as if programmed into OTP, so the pack
protects itself with no host.

**Not emulated (v1):** sleep / deep sleep / shutdown and wake, cell balancing, precharge /
predischarge, OCD2, OCD3, PF, die and FET temperature protections, CRC, OTP programming, the
LD-pin load detection (approximated by "no load demanded"), ADC noise.

**Simplifications to check on the EVM:** OCC recovers once discharging >= 200 mA (OCC Recovery);
OCD1 recovers on charge >= 200 mA or load removal, after Recovery Time; SCD recovers after SCD
Recovery Time; multi-function pin = cell thermistor if config bits [1:0] = 3 and [5:4] = 0.

Files
* `bq76952_emul.c/.h` - the emulator (also compiled into the Simulink platform, block SM_bms/AFE)
* `test/test_emul.c` - 37 checks, part of them through the unmodified Libre Solar host code: `make test`
* `bqe_sitl.c` - stand-alone SITL tool (simple pack + emulator, real time, same UDP link as the
  platform) for testing the Pi without MATLAB: `make && ./bqe_sitl <pi address> [--fault cov ...]`

SITL link (UDP): snapshot of the chip's direct-command memory to the host, port 50010, every step
(144 bytes: 'BQ76', step, last write acknowledged, time ms, registers 0x00-0x7F); host register
writes to port 50011 (40 bytes: sequence, register, length, data), one applied per step.
