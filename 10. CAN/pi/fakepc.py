"""Stand-in for the PC platform: sends BMS frame sets (as canTx.m) over UDP to bmsadv and
decodes the ADV frames it returns. usage: python fakepc.py"""
import socket, struct, time, sys
import cantools
db = cantools.database.load_file(sys.argv[1] if len(sys.argv) > 1 else "../bmsCan.dbc")
tx = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
rx = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); rx.bind(("127.0.0.1", 50001)); rx.setblocking(False)
def rec(name, vals):
    m = db.get_message_by_name(name)
    full = {s.name: 0 for s in m.signals}; full.update(vals)
    return struct.pack("<IB3x", m.frame_id, 8) + m.encode(full, strict=False)
def bms_set(v, i, state=7):
    out = [rec("f_BmsState", {"BmsState": state}), rec("f_PackLimits", {}),
           rec("f_PackValuesP0", {"Current": i, "BatteryVoltage": sum(v)}), rec("f_PackStateEstimation", {})]
    for mux in range(4):
        d = {"f_CellVoltages_Mux": mux}
        for j in range(4):
            g = 4*mux + j
            d[f"CellVoltage_{g:03d}"] = 1000*v[g] if g < 13 else 0
            d[f"CellVoltage_{g:03d}_invalidFlag"] = 0 if g < 13 else 1
        out.append(rec("f_CellVoltages", d))
    for mux in range(5):
        d = {"f_CellTemperatures_Mux": mux}
        for j in range(6):
            s = 6*mux + j
            d[f"CellTemperature_{s:03d}"] = 20 if s < 26 else 0
            d[f"CellTemperature_{s:03d}_invalidFlag"] = 0 if s < 26 else 1
        out.append(rec("f_CellTemperatures", d))
    return b"".join(out)
adv = {}
def drain():
    while True:
        try: data = rx.recv(4096)
        except BlockingIOError: return
        for k in range(0, len(data), 16):
            fid, = struct.unpack_from("<I", data, k)
            m = db.get_frame_id(fid) if False else db.get_message_by_frame_id(fid)
            adv.update(m.decode(data[k+8:k+16], decode_choices=False, allow_truncated=True))
def run(seconds, v, i):
    n = int(round(seconds / 0.1)); t0 = time.monotonic()
    for k in range(n):
        tx.sendto(bms_set(v, i), ("127.0.0.1", 50000))
        time.sleep(max(0.0, t0 + 0.1 * (k + 1) - time.monotonic())); drain()
    time.sleep(0.05); drain()
v = [3.725] * 13     # OCV 3.725 V = 50 % SOC in the placeholder BMS OCV table
print("1) BMS on, no record, rest: expect OCV init 50 %")
run(1.0, v, 0.0); print("   SocMin %.2f %% valid %d hb %d" % (adv["SocMin"], adv["Valid"], adv["Heartbeat"]))
print("2) 10 A discharge for 36 s: expect -%.3f %%" % (100*10*36/3600/23.45))
s0 = adv["SocMin"]; run(36.0, v, 10.0); drain()
print("   SocMin %.3f %% -> change %.3f %%" % (adv["SocMin"], adv["SocMin"] - s0))
sOff = adv["SocMin"]
print("3) BMS off 2 s: expect InputsStale, Valid 0"); time.sleep(2.0); drain()
print("   InputsStale %d Valid %d" % (adv["InputsStale"], adv["Valid"]))
print("4) BMS on again (short rest): expect stored SOC kept")
run(1.0, v, 0.0); print("   SocMin %.3f %% (before off %.3f %%) valid %d missed %d" % (adv["SocMin"], sOff, adv["Valid"], adv["FramesMissed"]))
