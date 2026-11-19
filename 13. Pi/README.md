# 13. Pi - Solaris advisory layer (Raspberry Pi 4B)

`solaris_host` is the host of the BQ76952: it reads its measurements and protection status,
runs the estimator set generated from `11. Estimator/estimator.slx`, and sends the ADV_* CAN
messages (`10. CAN`). It never switches the FETs: the BQ76952 protects the pack on its own and the
pack runs without the Pi.

Build on the Pi: `make`

Run
* SITL with the Simulink platform (PC at 192.168.50.1, PI_link = 1):
  `./solaris_host --sitl 192.168.50.1`
* SITL without MATLAB: on any Linux box `cd ../12.\ AFE && make && ./bqe_sitl <pi address>`, then on the Pi
  `./solaris_host --sitl <that box> --udp <that box>:50001`
* Real BQ76952EVM on I2C (J17: SDA, SCL, GND; REG1 3.3 V logic; remove the J15/J18 pull-up shunts;
  enable I2C with raspi-config): `./solaris_host --i2c /dev/i2c-1 --configure --can can0`
  (`--configure` writes `solaris_config.h` into the chip's RAM: the EVM's OTP does not hold these
  values; configuring turns the FETs off for about 1 s. Add `--crc` if the chip uses I2C CRC.)

Options: `--udp HOST:PORT` (ADV as UDP, sent from port 50013), `--can IF` (ADV on SocketCAN),
`--record FILE` (SOC record, default soc_record.txt), `--quiet`, `--verbose`.

Ports (SITL): snapshots in 50010, register writes out to the emulator's 50011 from port 50012,
ADV out from 50013 to the PC's 50001.

Files
* `solaris_host.c` - main program; `transport.c/.h` - I2C (i2c-dev, optional CRC) or SITL (UDP)
* `libresolar/` - Libre Solar bq769x2 host protocol, **unmodified** (Apache-2.0, see NOTICE.md)
* `compat/` - stand-ins for the few Zephyr APIs that code uses
* `solaris_config.h` - the pack's BQ76952 configuration (shared with the emulator)
* `solaris_can.c/.h` - generated CAN codec; `adv_map.c/.h` - generated (tools/genAdvMap.py)
* `gen/` - generated estimator code (refresh: `exportPiCode` in MATLAB, then copy to the Pi)
