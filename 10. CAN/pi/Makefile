# Raspberry Pi (64-bit Raspberry Pi OS): make
CFLAGS ?= -std=c99 -O2 -Wall -Wextra -Igen -I.
LDLIBS = -lm
GEN = gen/estimator.c gen/estimator_data.c gen/SE_Step.c
all: bmsadv canudp
bmsadv: bmsadv.c adv_map.c bms_can.c $(GEN)
	$(CC) $(CFLAGS) -o $@ $^ $(LDLIBS)
canudp: canudp.c
	$(CC) $(CFLAGS) -o $@ $^
clean:
	rm -f bmsadv canudp
.PHONY: all clean
