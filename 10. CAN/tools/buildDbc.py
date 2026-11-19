"""Build bmsCan.dbc: the CAN contract between the safety BMS (PC / OPAL-RT emulator, later a
real board) and the advisory estimator layer (Raspberry Pi).

BMS -> Pi : subset of the foxBMS 2 DBC (tools/dbc/foxbms.dbc, (c) Fraunhofer IISB, CC-BY-4.0),
            multiplexed messages trimmed to the 13 groups / 26 sensors of the 13S7P pack.
Pi -> PC  : ADV_* messages (this project), Intel byte order, 100 ms.
Raw value all-ones = "not available" (SNA) for ADV estimate fields.

usage: python buildDbc.py <foxbms.dbc> <out.dbc>
"""
import sys
import cantools
from cantools.database.can import Message, Signal
from cantools.database.conversion import BaseConversion

fox = cantools.database.load_file(sys.argv[1], strict=False)
KEEP = {  # message: highest multiplexer value kept (None = not multiplexed)
    "f_BmsState": None,              # 0x220 state, errors
    "f_PackLimits": None,            # 0x232 BMS current / power limits
    "f_PackValuesP0": None,          # 0x233 current, voltages, power
    "f_PackStateEstimation": None,   # 0x235 the BMS's own SOC / SOE / SOH
    "f_CellVoltages": 3,             # 0x250 4 groups per frame: mux 0..3 -> 16 >= 13
    "f_CellTemperatures": 4,         # 0x260 6 sensors per frame: mux 0..4 -> 30 >= 26
}
msgs = []
for name, muxMax in KEEP.items():
    m = fox.get_message_by_name(name)
    sigs = []
    for s in m.signals:
        if muxMax is not None and s.multiplexer_ids is not None and max(s.multiplexer_ids) > muxMax:
            continue
        sigs.append(s)
    msgs.append(Message(frame_id=m.frame_id, name=m.name, length=m.length, signals=sigs,
                        cycle_time=100, comment="foxBMS 2 (CC-BY-4.0); sent every 100 ms by the BMS emulator"
                        + ("" if muxMax is None else f"; mux 0..{muxMax}")))

def sig(name, start, length, scale=1, offset=0, signed=False, unit="", mux=None, muxer=False, comment="", muxSig=None):
    return Signal(name=name, start=start, length=length, byte_order="little_endian", is_signed=signed,
                  conversion=BaseConversion.factory(scale=scale, offset=offset), unit=unit,
                  minimum=offset + scale * (-(2 ** (length - 1)) if signed else 0),
                  maximum=offset + scale * ((2 ** (length - 1) - 1) if signed else 2 ** length - 1),
                  multiplexer_ids=mux, multiplexer_signal=muxSig, is_multiplexer=muxer, comment=comment)

SNA = " Raw all-ones = not available."
adv = [
    Message(0x380, "ADV_Status", 8, [
        sig("Heartbeat", 0, 8, comment="Increments every frame (wraps); stale if unchanged > 1 s"),
        sig("Valid", 8, 1, comment="1 = estimates usable (initialised, inputs fresh)"),
        sig("SocValid", 9, 1), sig("SohValid", 10, 1), sig("SopValid", 11, 1), sig("SoeValid", 12, 1),
        sig("InputsStale", 13, 1, comment="1 = BMS frames missing for longer than ADV_tStale"),
        sig("Initialising", 14, 1),
        sig("EstimatorSet", 16, 4, comment="Which estimator variant is running (0 = coulomb counting)"),
        sig("InputAge", 20, 12, unit="ms", comment="Age of the newest BMS measurement set used"),
        sig("BmsStateEcho", 32, 4, comment="foxBMS BmsState last received"),
        sig("FramesMissed", 40, 16, comment="BMS measurement sets missed since start (wraps)"),
    ], cycle_time=100, comment="Advisory layer status (this project)"),
    Message(0x381, "ADV_PackEstimates", 8, [
        sig("SocMin", 0, 14, 0.01, unit="%", comment="Lowest group SOC." + SNA),
        sig("SocMax", 14, 14, 0.01, unit="%", comment="Highest group SOC." + SNA),
        sig("SocSigma", 28, 10, 0.01, unit="%", comment="1-sigma SOC uncertainty." + SNA),
        sig("SohCapacity", 38, 10, 0.1, unit="%", comment="Capacity SOH, worst group (100 = new)." + SNA),
        sig("SohResistance", 48, 10, 0.1, unit="%", comment="Resistance SOH Rnew/R, worst group (100 = new)." + SNA),
    ], cycle_time=100, comment="Advisory SOC / SOH (this project)"),
    Message(0x382, "ADV_PowerEnergy", 8, [
        sig("SopDischarge", 0, 16, 1, unit="W", comment="Discharge power available over the horizon." + SNA),
        sig("SopCharge", 16, 16, 1, unit="W", comment="Charge power available over the horizon." + SNA),
        sig("SoeEnergy", 32, 16, 1, unit="Wh", comment="Remaining energy." + SNA),
        sig("SoePercent", 48, 14, 0.01, unit="%", comment="State of energy." + SNA),
    ], cycle_time=100, comment="Advisory SOP / SOE (this project)"),
    Message(0x383, "ADV_CurrentLimits", 8, [
        sig("IDischargeMax", 0, 12, 0.1, unit="A", comment="Discharge current available over the horizon." + SNA),
        sig("IChargeMax", 12, 12, 0.1, unit="A", comment="Charge current available over the horizon." + SNA),
        sig("Horizon", 24, 8, 1, unit="s", comment="SOP prediction horizon"),
    ], cycle_time=100, comment="Advisory current limits (this project)"),
    Message(0x384, "ADV_GroupSoc", 8,
        [sig("ADV_GroupSoc_Mux", 0, 8, muxer=True)] +
        [sig(f"GroupSoc_{4*m + k:03d}", 8 + 14 * k, 14, 0.01, unit="%", mux=[m], muxSig="ADV_GroupSoc_Mux",
             comment="Group SOC." + SNA) for m in range(4) for k in range(4)],
        cycle_time=100, comment="Advisory SOC per group, 4 per frame, mux 0..3 (this project)"),
]
db = cantools.database.Database(messages=msgs + adv, version="bmsCan 0.1")
cantools.database.dump_file(db, sys.argv[2])
print("\n".join(f"0x{m.frame_id:03X} {m.name:24s} {len(m.signals):3d} signals" for m in db.messages))
