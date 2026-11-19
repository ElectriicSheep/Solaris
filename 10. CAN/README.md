# 10. CAN - advisory messages from the Pi to the vehicle

`solarisCan.dbc` is the single source of truth; the MATLAB table and the Pi's C codec are
generated from it.

| ID | Message | Content |
|---|---|---|
| 0x380 | ADV_Status | Heartbeat, valid flags, BQ76952 summary (AfeState), input age, cycles missed |
| 0x381 | ADV_PackEstimates | SOC min / max / sigma, SOH capacity / resistance |
| 0x382 | ADV_PowerEnergy | SOP discharge / charge (W), SOE (Wh, %) |
| 0x383 | ADV_CurrentLimits | Current limits over the SOP horizon |
| 0x384 | ADV_GroupSoc | SOC per group, 4 per frame, mux 0..3 |
| 0x385 | ADV_AfeStatus | BQ76952 Safety Status A/B/C, FET status, stack voltage, current (passed through) |

All every 100 ms, Intel byte order. Estimate fields: raw all-ones = not available (not yet
estimated: SOC sigma, SOH, SOP, SOE). Without the Pi the vehicle receives none of these (the
BQ76952 has no CAN); a small relay MCU for basic status is planned (option C).

Arbitration (vehicle side): limits = the tighter of the BQ76952's and the advisory ones; SOC/SOE
for planning = advisory while ADV_Status.Valid and fresh; the BQ76952's protection never depends
on these messages.

* `tools/buildDbc.py` - writes solarisCan.dbc (Python, cantools)
* `tools/genMatlab.py` - writes `matlab/solarisCanDb.m` and `matlab/canVectors.json`
* `matlab/canPut.m`, `canGet.m`, `canBitPositions.m` - codec (07. Tests/checkCanCodec.m)
* `matlab/canRx.m` - decoder used by the platform (07. Tests/checkCanRx.m)
* Pi C codec: `13. Pi/solaris_can.c/.h`, from `python -m cantools generate_c_source --database-name solaris_can solarisCan.dbc`
