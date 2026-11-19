%% defineParameters.m
% Parameters and configuration sets for bmsPlatform.sldd.
% Safe to re-run: existing entries are overwritten with these values.
% Run after defineInterfaces.m when (re)creating the dictionary.

dd  = Simulink.data.dictionary.open("bmsPlatform.sldd");
sec = getSection(dd, "Design Data");

%       name                value    unit  description
p = { "LOAD_profile",       1,       "",   "Active load, selectable while running: 1 = CONST, 2 = PULSE, 3 = CYCLE A (loops), 4 = CYCLE A extended (loops); other = 0 A"
      "LOAD_iConst",        23.45,   "A",  "Constant discharge current (1C for one tube)"
      "LOAD_iPulse",        23.45,   "A",  "Pulse current"
      "LOAD_pulsePeriod",   600,     "s",  "Pulse period"
      "LOAD_pulseDuty",     50,      "",   "Pulse on-time, percent of period"
      "LOAD_scale",         1,       "",   "Scale factor on the CYCLE profiles"
      "PLANT_tAmbient",     288.15,  "K",  "Ambient temperature (match T0 in the battery params)"
      "PLANT_switchFault",  0,       "",   "Main switch fault injection, selectable while running: 0 = none, 1 = stuck open, 2 = welded (stuck closed); other = none"
      "SENS_faultType",     0,       "",   "Measurement fault injection (sensFaultInject.m): 0 none, 1 voltage offset, 2 temperature offset, 3 temperatures stop updating, 4 voltage channel open"
      "SENS_faultChannel",  1,       "",   "Fault channel: group 1-13 (voltage) or sensor 1-26 (temperature)"
      "SENS_faultValue",    0,       "",   "Offset magnitude for fault types 1 (V) and 2 (K)"
      "SENS_faultStart",    0,       "s",  "Fault start time"
      "SENS_faultDuration", 1e6,     "s",  "Fault duration (1e6 = permanent)"
      "SENS_faultRamp",     0,       "s",  "Offsets ramp in linearly over this time (0 = step)"
      "CAN_link",           0,       "",   "CAN link to the advisory estimators (variant, compile-time): 0 = none (advisory outputs not available), 1 = UDP to the Pi (CAN frames tunnelled, 10. CAN)"
      "CAN_Ts",             0.1,     "s",  "CAN transmit / receive period (= BMS_Ts: one measurement set per BMS step)"
      "ADV_tStale",         1,       "s",  "Advisory outputs stale if the ADV_Status heartbeat has not changed for this long"
      "ARB_socTol",         0.10,    "1",  "Advisory SOC rejected (and a mismatch flagged) if it differs from the BMS's by more than this" };

% BMS board peripherals seen by the BMS (BMS_HW block): real-time clock and the record
% read from non-volatile memory at power-up. A run starts at power-up; the record is
% what the previous power cycle saved. Default: no valid record (first power-up), so
% the BMS initialises SOC from OCV.
nvm = struct("socGroup", zeros(13, 1), "tSave", 0, "valid", false);
s = Simulink.Parameter(nvm);
s.DataType = "Bus: BMS_nvmRecord";
s.Description = "Record in the BMS's non-volatile memory at power-up (socGroup 0-1, tSave = RTC time of the save, s; valid)";
putEntry(sec, "HW_nvm", s);
s = Simulink.Parameter(1e6);
s.Unit = "s";
s.Description = "BMS real-time clock at the start of the run (arbitrary epoch); rest time = HW_rtcStart - HW_nvm.tSave";
putEntry(sec, "HW_rtcStart", s);

% Buttons on the battery (BMS_HW block): up to 4 presses each, rows [start duration] in
% s; rows with a negative start are unused. Default: power pressed for 1.2 s at start-up
% (the BMS starts OFF and needs the 1 s long press to switch on).
s = Simulink.Parameter([0 1.2; -1 0; -1 0; -1 0]);
s.Unit = "s";  s.Description = "Power button presses [start duration] (s), up to 4 rows; negative start = unused";
putEntry(sec, "HW_powerPress", s);
s = Simulink.Parameter([-1 0; -1 0; -1 0; -1 0]);
s.Unit = "s";  s.Description = "Reset button presses [start duration] (s), up to 4 rows; negative start = unused";
putEntry(sec, "HW_resetPress", s);

% LOAD_variant (compile-time variant choice) was replaced by LOAD_profile (run-time switch)
if exist(sec, "LOAD_variant"), deleteEntry(sec, "LOAD_variant"); end

for k = 1:size(p, 1)
    s = Simulink.Parameter(p{k,2});
    s.Unit        = p{k,3};
    s.Description = p{k,4};
    putEntry(sec, p{k,1}, s);
end

% Harness solver settings: fixed step, identical on desktop and on the OP5033 (RT-LAB
% needs a fixed step). 10 ms is set by the HIL interface (CAN frame timing, BMS
% reaction timing), not by the plant; checkPlantFixedStep.m checks its accuracy against
% a variable-step reference. The Simscape Solver Configuration block in PLANT must use
% the same step (local solver, backward Euler, fixed-cost iterations).
% An existing cfgHarness is edited in place, so other settings made in the GUI are kept.
platformTs = "0.01";   % s
cfgSec = getSection(dd, "Configurations");
if exist(cfgSec, "cfgHarness")
    cs = getValue(getEntry(cfgSec, "cfgHarness"));
else
    cs = Simulink.ConfigSet;
    cs.Name = "cfgHarness";
    set_param(cs, "StopTime", "10");
end
set_param(cs, "SolverType", "Fixed-step", "Solver", "ode1", "FixedStep", platformTs);
% Parameters stay tunable in generated code, so RT-LAB can change them while running
% (e.g. LOAD_iConst from a dashboard). Signal storage reuse and block reduction off,
% so every named signal remains visible to RT-LAB (slightly slower code; desktop
% results unchanged).
set_param(cs, "DefaultParameterBehavior", "Tunable", ...
              "OptimizeBlockIOStorage",   "off", ...
              "BlockReduction",           "off");
% Structure values on bus blocks (HW_nvm, BMS_stubOut) need simplified initialisation.
set_param(cs, "UnderspecifiedInitializationDetection", "Simplified");
putEntry(cfgSec, "cfgHarness", cs);

% BMS_stubOut: output of the STUB choice of SM_bms/BMS (RT-LAB builds, where the BMS is
% external). Contactor commanded closed so the plant conducts without a BMS; all other
% fields zero / default. BMS_outBus comes from the referenced bmsInterface.sldd, hence dd.
stub = Simulink.Bus.createMATLABStruct("BMS_outBus", [], [1 1], dd);
stub.contactorCmd = true;
putEntry(sec, "BMS_stubOut", stub);

% BMS limits sent in f_PackLimits. PLACEHOLDERS: the BMS has no limit calculation yet
% (charge/discharge limits are last on the list); RSL values of BMS_soaLim, pack level.
lim = struct("iDchg", 50, "iChg", 12.6, "pDchg", 50*13*3.6, "pChg", 12.6*13*4.2, "vMax", 13*4.23, "vMin", 13*2.80);
s = Simulink.Parameter(lim);
s.Description = "Pack limits broadcast by the BMS emulator (f_PackLimits): iDchg iChg (A), pDchg pChg (W), vMax vMin (V); placeholders = RSL values";
putEntry(sec, "CAN_bmsLim", s);


saveChanges(dd);
fprintf("Parameters and cfgHarness written to bmsPlatform.sldd\n");

function putEntry(sec, name, value)
    % Add the entry, or overwrite it if it already exists
    if exist(sec, name)
        setValue(getEntry(sec, name), value);
    else
        addEntry(sec, name, value);
    end
end