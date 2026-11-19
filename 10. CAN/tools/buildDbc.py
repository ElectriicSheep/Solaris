"""Build solarisCan.dbc: the advisory CAN messages the Raspberry Pi sends to the vehicle
(state estimates, plus the BQ76952's protection status passed through).
Intel byte order, 100 ms. Raw value all-ones = "not available" (SNA) for estimate fields.
usage: python buildDbc.py <out.dbc>
"""
import sys
import cantools
from cantools.database.can import Message, Signal
from cantools.database.conversion import BaseConversion

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
        sig("InputsStale", 13, 1, comment="1 = BQ76952 not answering (no measurement for longer than ADV_tStale)"),
        sig("Initialising", 14, 1),
        sig("EstimatorSet", 16, 4, comment="Which estimator variant is running (0 = coulomb counting)"),
        sig("InputAge", 20, 12, unit="ms", comment="Age of the newest BQ76952 measurement used"),
        sig("AfeState", 32, 4, comment="BQ76952 summary: bit0 CHG FET on, bit1 DSG FET on, bit2 safety fault active, bit3 CONFIG_UPDATE"),
        sig("FramesMissed", 40, 16, comment="Measurement cycles missed since start (wraps)"),
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
    Message(0x385, "ADV_AfeStatus", 8, [
        sig("SafetyStatusA", 0, 8, comment="BQ76952 Safety Status A: bit2 CUV, 3 COV, 4 OCC, 5 OCD1, 6 OCD2, 7 SCD"),
        sig("SafetyStatusB", 8, 8, comment="BQ76952 Safety Status B: bit0 UTC, 1 UTD, 2 UTINT, 4 OTC, 5 OTD, 6 OTINT, 7 OTF"),
        sig("SafetyStatusC", 16, 8, comment="BQ76952 Safety Status C"),
        sig("FetStatus", 24, 8, comment="BQ76952 FET Status: bit0 CHG, 1 PCHG, 2 DSG, 3 PDSG"),
        sig("StackVoltage", 32, 16, 0.01, unit="V", comment="Stack voltage as measured by the BQ76952"),
        sig("Current", 48, 16, 0.01, signed=True, unit="A", comment="Pack current as measured by the BQ76952, discharge positive"),
    ], cycle_time=100, comment="BQ76952 protection status, passed through by the Pi"),
]
db = cantools.database.Database(messages=adv, version="solarisCan 0.2")
cantools.database.dump_file(db, sys.argv[1])
print("\n".join(f"0x{m.frame_id:03X} {m.name:20s} {len(m.signals):3d} signals" for m in db.messages))
