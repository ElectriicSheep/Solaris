/* transport.h - how the host reaches the BQ76952.
 *   I2C  (real hardware): Linux i2c-dev, e.g. /dev/i2c-1, 7-bit address 0x08, optional CRC.
 *   SITL (emulator):      UDP. The emulator sends a snapshot of the chip's direct-command
 *                         memory every step (port 50010); reads are served from the latest
 *                         snapshot; each write is sent (port 50011) and waits until a snapshot
 *                         acknowledges it, so the next read sees its effect (as on the chip).
 *                         Writes are sent from UDP port 50012 (fixed: the Simulink block filters on it).
 * Everything above this layer (Libre Solar interface, host logic) is identical for both. */
#ifndef TRANSPORT_H
#define TRANSPORT_H
#include <stddef.h>
#include <stdint.h>
#include "zephyr_compat.h"

int tp_open_i2c(const char *devpath, uint8_t addr, int crc);
int tp_open_sitl(const char *emulHost, int snapPort, int writePort);
int tp_write(const struct device *dev, uint8_t reg, const uint8_t *data, size_t n);
int tp_read(const struct device *dev, uint8_t reg, uint8_t *data, size_t n);
/* SITL: drain received snapshots; returns age (s) of the newest one, or -1 if none yet.
 * I2C: returns 0 (the chip is read directly). */
double tp_poll(void);
int tp_is_sitl(void);
#endif
