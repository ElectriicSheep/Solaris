/* zephyr_compat.h - minimal stand-ins for the Zephyr APIs used by the (unmodified) Libre Solar
 * bq769x2 interface layer, so it builds as plain Linux C. Only what that layer touches. */
#ifndef ZEPHYR_COMPAT_H
#define ZEPHYR_COMPAT_H
#ifndef _DEFAULT_SOURCE
#define _DEFAULT_SOURCE
#endif
#include <errno.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <unistd.h>

struct device { const char *name; const void *config; void *data; };
struct i2c_dt_spec { const void *bus; uint16_t addr; };
struct gpio_dt_spec { const void *port; uint8_t pin; uint16_t dt_flags; };
struct bms_ic_data;

#ifndef CONFIG_BMS_IC_MAX_THERMISTORS
#define CONFIG_BMS_IC_MAX_THERMISTORS 9
#endif
#ifndef CONFIG_BMS_IC_LOG_LEVEL
#define CONFIG_BMS_IC_LOG_LEVEL 2
#endif
extern int bq_log_level;                               /* 0 off, 1 errors, 2 + warnings, 3 + info */
#define LOG_MODULE_REGISTER(...)
#define LOG_ERR(...) do { if (bq_log_level >= 1) { fprintf(stderr, "bq769x2 ERR: " __VA_ARGS__); fputc('\n', stderr); } } while (0)
#define LOG_WRN(...) do { if (bq_log_level >= 2) { fprintf(stderr, "bq769x2 WRN: " __VA_ARGS__); fputc('\n', stderr); } } while (0)
#define LOG_INF(...) do { if (bq_log_level >= 3) { fprintf(stdout, "bq769x2: " __VA_ARGS__); fputc('\n', stdout); } } while (0)
#define LOG_DBG(...) do { } while (0)
#define __ASSERT(c, ...) do { if (!(c)) { fprintf(stderr, "bq769x2 assert failed: %s:%d\n", __FILE__, __LINE__); } } while (0)
#define __maybe_unused __attribute__((unused))
#define k_usleep(us) bq_usleep(us)
void bq_usleep(int us);                                /* transport-aware delay (see transport.c) */
#endif
