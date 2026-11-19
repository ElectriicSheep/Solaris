# 10. CAN - BMS <-> advisory estimator contract

`bmsCan.dbc` is the single source of truth. Everything else here is generated from it.

| Direction | ID | Message | Content |
|---|---|---|---|
| BMS -> Pi | 0x220 | f_BmsState | BMS state, error / warning flags |
| BMS -> Pi | 0x232 | f_PackLimits | BMS current / power / voltage limits |
| BMS -> Pi | 0x233 | f_PackValuesP0 | Pack current, battery / bus voltage, power |
| BMS -> Pi | 0x235 | f_PackStateEstimation | The BMS's own SOC / SOE / SOH |
| BMS -> Pi | 0x250 | f_CellVoltages | 4 groups per frame + invalid flags, mux 0..3 (13 used) |
| BMS -> Pi | 0x260 | f_CellTemperatures | 6 sensors per frame + invalid flags, mux 0..4 (26 used), 1 degC |
| Pi -> PC | 0x380 | ADV_Status | Heartbeat, valid flags, input age, frames missed |
| Pi -> PC | 0x381 | ADV_PackEstimates | SOC min / max / sigma, SOH capacity / resistance |
| Pi -> PC | 0x382 | ADV_PowerEnergy | SOP discharge / charge (W), SOE (Wh, %) |
| Pi -> PC | 0x383 | ADV_CurrentLimits | Current limits over the SOP horizon |
| Pi -> PC | 0x384 | ADV_GroupSoc | SOC per group, 4 per frame, mux 0..3 |

* All messages every 100 ms (a choice: foxBMS's own example config sends cell voltages
  far slower). A "cell" in the foxBMS messages is one 7P group here.
* ADV estimate fields: raw all-ones = not available (not yet estimated).
* Arbitration (vehicle side): limits = the tighter of BMS and advisory; SOC / SOE for
  planning = advisory while ADV_Status.Valid and fresh, else the BMS's; irreversible
  decisions use the more conservative value. The BMS's protection never depends on ADV.

Files
* `tools/buildDbc.py` - builds bmsCan.dbc from foxbms.dbc + the ADV definitions (Python, cantools)
* `tools/genMatlab.py` - generates `matlab/bmsCanDb.m` and `matlab/canVectors.json`
* `matlab/canPut.m`, `canGet.m`, `canBitPositions.m` - MATLAB codec (checked by 07. Tests/checkCanCodec.m)
* `pi/bms_can.c/.h` - C codec for the Pi, generated: `python -m cantools generate_c_source --database-name bms_can bmsCan.dbc`

foxBMS messages: from foxBMS 2 `tools/dbc/foxbms.dbc`, (c) Fraunhofer IISB, licensed CC-BY-4.0
(https://creativecommons.org/licenses/by/4.0/); trimmed to the messages and multiplexer values above.
