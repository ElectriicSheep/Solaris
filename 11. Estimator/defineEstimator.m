%% defineEstimator.m
% Creates estimator.sldd: everything estimator.slx needs (buses, parameters, code-generation
% configuration), so the estimator set is self-contained (it no longer uses the BMS's dictionary).
% Generated 2026-11-19 from the previous definitions; edit here from now on. The BMS_ prefix is
% historical (these were the BMS's SE layer); temperatures cut to the 7 thermistors of the BQ76952.

here = fileparts(mfilename("fullpath"));  f = fullfile(here, "estimator.sldd");
Simulink.data.dictionary.closeAll("estimator.sldd", "-discard");
if isfile(f), delete(f); end
dd = Simulink.data.dictionary.create(f);  sec = getSection(dd, "Design Data");

b = Simulink.Bus;  b.Description = "Record kept in non-volatile memory over a power cycle (contract)";
b.Elements = [ ...
    el("socGroup", 13, "1", "double", "Group SOC when the record was saved, 0-1")
    el("tSave", 1, "s", "double", "Real-time-clock time of the save")
    el("valid", 1, "", "boolean", "Record intact (in hardware: checksum correct; false if never written)")
    ];
addEntry(sec, "BMS_nvmRecord", b);

b = Simulink.Bus;  b.Description = "BMSVL -> SOA, SE, BMS: validated values and extremes";
b.Elements = [ ...
    el("vGroup", 13, "V", "double", "Validated group voltages")
    el("iPack", 1, "A", "double", "Validated pack current")
    el("tSensor", 7, "K", "double", "Validated temperatures")
    el("vMin", 1, "V", "double", "Lowest VALID group voltage (last valid value held if none valid)")
    el("vMax", 1, "V", "double", "Highest VALID group voltage (last valid value held if none valid)")
    el("tMin", 1, "K", "double", "Lowest VALID temperature (last valid value held if none valid)")
    el("tMax", 1, "K", "double", "Highest VALID temperature (last valid value held if none valid)")
    el("allValid", 1, "", "boolean", "Every channel plausible")
    el("contactorFb", 1, "", "boolean", "Validated main contactor feedback: true = closed")
    el("measReady", 1, "", "boolean", "Every sensor type has delivered a new sample since start-up (latched)")
    el("vMinIdx", 1, "", "uint8", "Group (1-13) with the lowest valid voltage; 0 = none valid yet")
    el("vMaxIdx", 1, "", "uint8", "Group (1-13) with the highest valid voltage; 0 = none valid yet")
    el("tMinIdx", 1, "", "uint8", "Sensor (1-26) with the lowest valid temperature; 0 = none valid yet")
    el("tMaxIdx", 1, "", "uint8", "Sensor (1-26) with the highest valid temperature; 0 = none valid yet")
    ];
addEntry(sec, "BMS_validData", b);

b = Simulink.Bus;  b.Description = "BMS board inputs: real-time clock and the stored record (contract)";
b.Elements = [ ...
    el("rtcNow", 1, "s", "double", "Real-time clock now (battery-backed; keeps time while the BMS is off)")
    el("nvm", 1, "", "Bus: BMS_nvmRecord", "Record read from non-volatile memory at power-up")
    el("powerBtn", 1, "", "boolean", "Power button pressed (long press BMS_tPowerPress: on / off)")
    el("resetBtn", 1, "", "boolean", "Reset button pressed (long press BMS_tResetPress: restart, SOC from OCV)")
    ];
addEntry(sec, "BMS_hwIn", b);

b = Simulink.Bus;  b.Description = "PWR -> all layers: power and reset state from the buttons";
b.Elements = [ ...
    el("awake", 1, "", "boolean", "BMS on (woken by a power long press, until the next one)")
    el("boot", 1, "", "boolean", "One-step pulse: every layer restarts as after a power-up (wake or reset)")
    el("reset", 1, "", "boolean", "One-step pulse: reset long press (SOC from OCV, ERROR latch cleared)")
    el("powerOn", 1, "", "boolean", "One-step pulse: woken by the power button")
    el("powerOff", 1, "", "boolean", "One-step pulse: switched off by the power button")
    ];
addEntry(sec, "BMS_pwrData", b);

b = Simulink.Bus;  b.Description = "SE -> output: state estimates";
b.Elements = [ ...
    el("socGroup", 13, "1", "double", "Estimated group SOC, 0-1")
    el("sohR", 13, "1", "double", "Resistance SOH per group (1 = new)")
    el("sohQ", 13, "1", "double", "Capacity SOH per group (1 = new)")
    el("socPack", 1, "1", "double", "Pack SOC (minimum group SOC)")
    el("sohPack", 1, "1", "double", "Pack SOH (worst group)")
    el("socInitMethod", 1, "", "uint8", "How SOC was initialised: 0 not yet, 1 stored, 3 OCV (2 not used)")
    el("socInitMismatch", 1, "", "boolean", "Stored SOC disagreed with OCV beyond BMS_socMismatchTol (OCV used)")
    el("socInitDiff", 1, "1", "double", "Largest |stored - OCV| SOC difference over the groups at initialisation")
    el("socInitDiffIdx", 1, "", "uint8", "Group (1-13) with that largest difference; 0 = not evaluated")
    el("socInitRest", 1, "s", "double", "Rest time since the stored record was saved (rtcNow - tSave); -1 = no stored record used (none valid, or reset)")
    el("socRecal", 1, "", "boolean", "SOC being recalibrated from OCV: pack at rest (|iPack| < BMS_iRest) for BMS_tRestRecal")
    el("nvm", 1, "", "Bus: BMS_nvmRecord", "Record to save (current SOC, time, valid once SOC is initialised)")
    ];
addEntry(sec, "BMS_seData", b);

p = Simulink.Parameter(0.1);  p.Unit = "s";
p.Description = "BMS task period: the rate at which the BMS reads its inputs and runs MEAS..BMS (must be a multiple of the 10 ms base rate in cfgBMS)";  addEntry(sec, "BMS_Ts", p);
p = Simulink.Parameter(23.45);  p.Unit = "A*h";
p.Description = "Nominal (new) parallel-group capacity Q_nom: 7 cells x 3.35 Ah (placeholder). Actual capacity per group Q_act = BMS_Qnom * SOH_Q, used by coulomb counting.";  addEntry(sec, "BMS_Qnom", p);
p = Simulink.Parameter([0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1]);  p.Unit = "1";
p.Description = "SOC breakpoints of the BMS OCV table (placeholder)";  addEntry(sec, "BMS_ocvSoc", p);
p = Simulink.Parameter([2.65 3.38 3.51 3.59 3.655 3.725 3.795 3.875 3.97 4.075 4.2]);  p.Unit = "V";
p.Description = "Cell (= group) OCV at BMS_ocvSoc, strictly increasing (placeholder)";  addEntry(sec, "BMS_ocvV", p);
p = Simulink.Parameter(7200);  p.Unit = "s";
p.Description = "Rest time since switch-off after which OCV is used at start-up (cells relaxed); shorter rests keep the stored SOC (placeholder)";  addEntry(sec, "BMS_tRelax", p);
p = Simulink.Parameter(0.1);  p.Unit = "1";
p.Description = "Largest stored-vs-OCV SOC difference explained by OCV error; beyond it the battery is taken as recharged or swapped while off and OCV is used";  addEntry(sec, "BMS_socMismatchTol", p);
p = Simulink.Parameter(0.2);  p.Unit = "A";
p.Description = "Current magnitude below which the pack is at rest: no charge temperature window (SOA), rest timer for SOC recalibration (SE) (foxBMS default 200 mA)";  addEntry(sec, "BMS_iRest", p);
p = Simulink.Parameter(600);  p.Unit = "s";
p.Description = "Time at rest (|iPack| < BMS_iRest, switch closed, all valid) after which SOC is set from OCV while the rest lasts (foxBMS example: 10 min; placeholder)";  addEntry(sec, "BMS_tRestRecal", p);

% code generation: ERT, 64-bit ARM (Raspberry Pi), code only, single rate at BMS_Ts (cfgEstimatorDef.m
% was saved from the configuration with saveAs)
cs = cfgEstimatorDef();  cs.Name = "cfgEstimator";
addEntry(getSection(dd, "Configurations"), "cfgEstimator", cs);
saveChanges(dd);
fprintf("estimator.sldd created\n");

function e = el(name, dims, unit, dataType, description)
    e = Simulink.BusElement;  e.Name = name;  e.Dimensions = dims;
    e.Unit = unit;  e.DataType = dataType;  e.Description = description;
end
