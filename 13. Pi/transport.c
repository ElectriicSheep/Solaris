#define _DEFAULT_SOURCE 1
/* transport.c - see transport.h. The I2C byte layout and CRC handling follow the Libre Solar
 * bq769x2 driver (bq769x2.c, Apache-2.0); written here for Linux i2c-dev. */
#include "transport.h"

#include <arpa/inet.h>
#include <fcntl.h>
#include <linux/i2c-dev.h>
#include <linux/i2c.h>
#include <poll.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <time.h>

static int g_sitl = 0, g_fd = -1, g_crc = 0;
static uint8_t g_addr = 0x08;
static struct sockaddr_in g_emul;
static int g_tx = -1;
static uint8_t g_snap[144];
static int g_have = 0;
static double g_tSnap = 0;
static uint32_t g_seq = 0;

static double now_s(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec + 1e-9 * t.tv_nsec; }
void bq_usleep(int us) { if (!g_sitl && us > 0) usleep((useconds_t)us); }
int tp_is_sitl(void) { return g_sitl; }
static uint32_t u32(const uint8_t *p);
uint32_t tp_chip_time_ms(void) { return (g_sitl && g_have) ? u32(g_snap + 12) : 0; }

/* ---------- I2C ---------- */
static uint8_t crc8(uint8_t crc, const uint8_t *d, size_t n) {   /* CRC-8 CCITT, poly 0x07 */
    while (n--) { crc ^= *d++; for (int i = 0; i < 8; i++) crc = (uint8_t)(crc & 0x80 ? (crc << 1) ^ 0x07 : crc << 1); }
    return crc;
}
int tp_open_i2c(const char *devpath, uint8_t addr, int crc) {
    g_fd = open(devpath, O_RDWR);
    if (g_fd < 0) { perror(devpath); return -1; }
    g_addr = addr; g_crc = crc; g_sitl = 0;
    return 0;
}
static int i2c_xfer(struct i2c_msg *m, int n) {
    struct i2c_rdwr_ioctl_data x = { m, (uint32_t)n };
    return ioctl(g_fd, I2C_RDWR, &x) < 0 ? -EIO : 0;
}
static int i2c_write(uint8_t reg, const uint8_t *d, size_t n) {
    uint8_t buf[2 + 2 * 32];
    size_t len = 0;
    if (n < 1 || n > 32) return -EINVAL;
    buf[len++] = reg;
    if (g_crc) {   /* first CRC covers target address, register, data[0]; later ones each byte */
        uint8_t h[3] = { (uint8_t)(g_addr << 1), reg, d[0] };
        buf[len++] = d[0]; buf[len++] = crc8(0, h, 3);
        for (size_t i = 1; i < n; i++) { buf[len++] = d[i]; buf[len++] = crc8(0, &d[i], 1); }
    } else { memcpy(buf + 1, d, n); len += n; }
    struct i2c_msg m = { g_addr, 0, (uint16_t)len, buf };
    return i2c_xfer(&m, 1);
}
static int i2c_read(uint8_t reg, uint8_t *d, size_t n) {
    if (n < 1 || n > 32) return -EINVAL;
    uint8_t raw[64];
    size_t rn = g_crc ? 2 * n : n;
    struct i2c_msg m[2] = { { g_addr, 0, 1, &reg }, { g_addr, I2C_M_RD, (uint16_t)rn, raw } };
    if (i2c_xfer(m, 2)) return -EIO;
    if (!g_crc) { memcpy(d, raw, n); return 0; }
    uint8_t h[4] = { (uint8_t)(g_addr << 1), reg, (uint8_t)((g_addr << 1) | 1), raw[0] };
    if (crc8(0, h, 4) != raw[1]) return -EIO;          /* first CRC: address, register, address+R, data */
    d[0] = raw[0];
    for (size_t i = 1; i < n; i++) { if (crc8(0, &raw[2 * i], 1) != raw[2 * i + 1]) return -EIO; d[i] = raw[2 * i]; }
    return 0;
}

/* ---------- SITL ---------- */
int tp_open_sitl(const char *emulHost, int snapPort, int writePort) {
    g_fd = socket(AF_INET, SOCK_DGRAM, 0);
    struct sockaddr_in la; memset(&la, 0, sizeof la);
    la.sin_family = AF_INET; la.sin_port = htons((uint16_t)snapPort); la.sin_addr.s_addr = INADDR_ANY;
    if (bind(g_fd, (struct sockaddr *)&la, sizeof la) < 0) { perror("snapshot port"); return -1; }
    g_tx = socket(AF_INET, SOCK_DGRAM, 0);
    struct sockaddr_in sa; memset(&sa, 0, sizeof sa);           /* fixed source port: the Simulink */
    sa.sin_family = AF_INET; sa.sin_port = htons(50012);        /* UDP Receive block filters on it */
    sa.sin_addr.s_addr = INADDR_ANY;
    if (bind(g_tx, (struct sockaddr *)&sa, sizeof sa) < 0) { perror("write source port 50012"); return -1; }
    memset(&g_emul, 0, sizeof g_emul);
    g_emul.sin_family = AF_INET; g_emul.sin_port = htons((uint16_t)writePort);
    if (inet_pton(AF_INET, emulHost, &g_emul.sin_addr) != 1) { fprintf(stderr, "bad emulator address %s\n", emulHost); return -1; }
    g_sitl = 1;
    return 0;
}
static uint32_t u32(const uint8_t *p) { return (uint32_t)p[0] | (uint32_t)p[1] << 8 | (uint32_t)p[2] << 16 | (uint32_t)p[3] << 24; }
static void drain(int timeoutMs) {
    struct pollfd pf = { g_fd, POLLIN, 0 };
    while (poll(&pf, 1, timeoutMs) > 0) {
        uint8_t b[256];
        ssize_t n = recv(g_fd, b, sizeof b, 0);
        if (n == 144 && b[0] == 'B' && b[1] == 'Q' && b[2] == '7' && b[3] == '6') { memcpy(g_snap, b, 144); g_have = 1; g_tSnap = now_s(); }
        timeoutMs = 0;
    }
}
double tp_poll(void) {
    if (!g_sitl) return 0;
    drain(0);
    return g_have ? now_s() - g_tSnap : -1;
}
static int sitl_write(uint8_t reg, const uint8_t *d, size_t n) {
    if (n > 32) return -EINVAL;
    uint8_t p[40]; memset(p, 0, sizeof p);
    uint32_t s = ++g_seq;
    if (s == 0) s = ++g_seq;
    for (int i = 0; i < 4; i++) p[i] = (s >> (8 * i)) & 0xFF;
    p[4] = reg; p[5] = (uint8_t)n; memcpy(p + 6, d, n);
    for (int attempt = 0; attempt < 3; attempt++) {
        sendto(g_tx, p, sizeof p, 0, (struct sockaddr *)&g_emul, sizeof g_emul);
        double t0 = now_s();
        while (now_s() - t0 < 0.3) {                   /* wait for the acknowledging snapshot */
            drain(5);
            if (g_have && (int32_t)(u32(g_snap + 8) - s) >= 0) return 0;
        }
    }
    return -EIO;
}
static int sitl_read(uint8_t reg, uint8_t *d, size_t n) {
    drain(0);
    if (!g_have || reg + n > 128) return -EIO;
    memcpy(d, g_snap + 16 + reg, n);
    return 0;
}

int tp_write(const struct device *dev, uint8_t reg, const uint8_t *data, size_t n) { (void)dev; return g_sitl ? sitl_write(reg, data, n) : i2c_write(reg, data, n); }
int tp_read(const struct device *dev, uint8_t reg, uint8_t *data, size_t n) { (void)dev; return g_sitl ? sitl_read(reg, data, n) : i2c_read(reg, data, n); }
