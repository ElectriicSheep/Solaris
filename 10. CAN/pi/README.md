# Pi advisory estimator (Raspberry Pi 4B, Raspberry Pi OS Lite 64-bit)

    PC (Simulink, CAN_link = 1) --UDP 50000--> canudp --> vcan0 --> bmsadv (estimator)
    PC <--UDP 50001-- canudp <-- vcan0 <-- bmsadv (ADV_* frames)

* `bmsadv` - runs the code generated from `11. Estimator/estimator.slx` once per BMS
  measurement set; sends ADV_Status / PackEstimates / PowerEnergy / CurrentLimits / GroupSoc.
  SOC record file `soc_record.txt` = the BMS's non-volatile memory (saved when BMS frames
  stop and every 60 s). Console: one line per second + start-up / stop messages.
* `canudp` - UDP <-> SocketCAN bridge (not needed once a CAN HAT and real CAN are used).
* `gen/` - generated estimator code (refresh: `exportPiCode` in MATLAB, then copy again).
* `bms_can.c/.h` - CAN codec generated from bmsCan.dbc.

Build on the Pi:  `make`
Run (two terminals, or add `&`):
    ./canudp -i vcan0 -p 192.168.50.1
    ./bmsadv -i vcan0
Watch the bus:  `candump vcan0`
Test without the PC (UDP mode, on any Linux box with python3 + cantools):
    ./bmsadv -u 50000 -p 127.0.0.1 -r 50001 &   python3 fakepc.py ../bmsCan.dbc
