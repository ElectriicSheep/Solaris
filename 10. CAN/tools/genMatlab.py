"""Generate solarisCanDb.m (MATLAB signal table) and canVectors.json (test vectors) from solarisCan.dbc.
usage: python genMatlab.py solarisCan.dbc outDir"""
import sys, json, random, os
import cantools
db = cantools.database.load_file(sys.argv[1]); out = sys.argv[2]
L = ["function S = solarisCanDb()", "%SOLARISCANDB  CAN signal table generated from solarisCan.dbc by tools/genMatlab.py - do not edit.",
     "%   S.<message>.id      frame identifier",
     "%   S.<message>.<signal> = [startBit length intel signed scale offset]",
     "%   startBit as in the DBC: Intel = least significant bit, Motorola = most significant bit.",
     "%   S.<message>.<family>(i+1,:) = spec of <family>_<i> (e.g. CellVoltage, CellVoltage_invalidFlag, GroupSoc)",
     "%   Use with canPut / canGet."]
for m in db.messages:
    L.append(f"S.{m.name}.id = uint32({m.frame_id});")
    for s in m.signals:
        intel = 1 if s.byte_order == "little_endian" else 0
        L.append(f"S.{m.name}.{s.name} = [{s.start} {s.length} {intel} {int(s.is_signed)} {s.scale!r} {s.offset!r}];")
# indexed families (CellVoltage_000.., CellVoltage_000_invalidFlag.., GroupSoc_000..) as
# matrices, row i+1 = signal i, for code generation (no dynamic field names)
import re
fam = {}
for m in db.messages:
    for sg in m.signals:
        r = re.fullmatch(r"(.+?)_(\d{3})(_invalidFlag)?", sg.name)
        if r:
            key = (m.name, r.group(1) + (r.group(3) or ""))
            intel = 1 if sg.byte_order == "little_endian" else 0
            fam.setdefault(key, {})[int(r.group(2))] = f"{sg.start} {sg.length} {intel} {int(sg.is_signed)} {sg.scale!r} {sg.offset!r}"
for (mn, fn), rows in fam.items():
    n = max(rows) + 1
    assert sorted(rows) == list(range(n)), (mn, fn)
    L.append(f"S.{mn}.{fn} = [" + "; ".join(rows[i] for i in range(n)) + "];")
L.append("end")
open(os.path.join(out, "solarisCanDb.m"), "w", newline="\r\n").write("\n".join(L) + "\n")

random.seed(1)
vec = []
for m in db.messages:
    muxIds = sorted({i for s in m.signals if s.multiplexer_ids for i in s.multiplexer_ids}) or [None]
    for mux in muxIds:
        for _ in range(3):
            vals = {}
            for s in m.signals:
                if s.multiplexer_ids and mux not in s.multiplexer_ids: continue
                if s.is_multiplexer: vals[s.name] = mux; continue
                lo = -(2 ** (s.length - 1)) if s.is_signed else 0
                hi = (2 ** (s.length - 1) - 1) if s.is_signed else 2 ** s.length - 1
                vals[s.name] = random.randint(lo, hi) * s.scale + s.offset
            data = m.encode(vals, scaling=True, strict=False)
            vec.append({"msg": m.name, "values": vals, "bytes": list(data)})
json.dump(vec, open(os.path.join(out, "canVectors.json"), "w"))
print(len(vec), "vectors")
