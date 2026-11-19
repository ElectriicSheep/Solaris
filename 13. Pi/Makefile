# Solaris advisory layer for the Raspberry Pi (64-bit Raspberry Pi OS):  make
CFLAGS ?= -std=c99 -O2 -Wall -Wextra -Icompat -Ilibresolar -Igen -I.
LDLIBS = -lm
GEN = gen/estimator.c gen/estimator_data.c gen/SE_Step.c
SRC = solaris_host.c transport.c adv_map.c solaris_can.c libresolar/bq769x2_interface.c $(GEN)
all: solaris_host
solaris_host: $(SRC)
	$(CC) $(CFLAGS) -o $@ $(SRC) $(LDLIBS)
clean:
	rm -f solaris_host
.PHONY: all clean
