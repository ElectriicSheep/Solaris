# BQ76952 emulator: unit test and stand-alone SITL tool (Linux / WSL / Pi).
# Shares solaris_config.h and the Libre Solar register map with the Pi host in ../13. Pi.
PI = ../13.\ Pi
CFLAGS ?= -std=c99 -O2 -Wall -Wextra -I. -I$(PI) -I$(PI)/libresolar -I$(PI)/compat
all: test_emul bqe_sitl
test_emul: test/test_emul.c bq76952_emul.c
	$(CC) $(CFLAGS) -Wno-sign-compare -o $@ test/test_emul.c bq76952_emul.c $(PI)/libresolar/bq769x2_interface.c -lm
bqe_sitl: bqe_sitl.c bq76952_emul.c
	$(CC) $(CFLAGS) -o $@ bqe_sitl.c bq76952_emul.c -lm
test: test_emul
	./test_emul
clean:
	rm -f test_emul bqe_sitl
.PHONY: all test clean
