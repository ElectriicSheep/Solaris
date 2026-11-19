%% buildEstimator.m
% Builds estimator.slx: the advisory estimator set that runs on the Raspberry Pi.
% Inputs are what the Pi gets over CAN from the safety BMS (10. CAN/bmsCan.dbc), plus
% the Pi's own clock and SOC record file; output is BMS_seData.
% The estimator layer starts as a copy of the BMS's SE layer (coulomb counting, start-up
% SOC from stored record / OCV, rest recalibration). From here it is meant to diverge:
% the safety BMS keeps its simple estimate, the Pi gets EKF / RLS / SOH / SOP / SOE.
% Re-running rebuilds the model from bms/SE (overwrites estimator.slx).

mdl = "estimator";  here = fileparts(mfilename("fullpath"));
ddFile = "estimator.sldd";
if ~isfile(fullfile(here, ddFile))
    dd = Simulink.data.dictionary.create(fullfile(here, ddFile));
else
    dd = Simulink.data.dictionary.open(fullfile(here, ddFile));
end
if ~any(strcmp(dd.DataSources, "bms.sldd")), addDataSource(dd, "bms.sldd"); end
% configuration: as cfgBMS (ERT, ARM 64-bit, code only) but single rate at BMS_Ts
src = getValue(getEntry(getSection(Simulink.data.dictionary.open("bms.sldd"), "Configurations"), "cfgBMS"));
cs = copy(src);  cs.Name = "cfgEstimator";
set_param(cs, "FixedStep", "BMS_Ts");
sec = getSection(dd, "Configurations");
if exist(sec, "cfgEstimator"), setValue(getEntry(sec, "cfgEstimator"), cs); else, addEntry(sec, "cfgEstimator", cs); end
saveChanges(dd);

if bdIsLoaded(mdl), close_system(mdl, 0); end
f = fullfile(here, mdl + ".slx");  if isfile(f), delete(f); end
new_system(mdl);  set_param(mdl, "DataDictionary", ddFile);
ref = Simulink.ConfigSetRef;  ref.Name = "cfgEstimatorRef";  ref.SourceName = "cfgEstimator";
attachConfigSet(mdl, ref);  setActiveConfigSet(mdl, "cfgEstimatorRef");

% ---- inputs (one value per BMS measurement set, period BMS_Ts)
in = { "vGroup",  "double",  "13", "Group voltages from f_CellVoltages (V)"
       "vValid",  "boolean", "13", "Not f_CellVoltages invalid flag"
       "iPack",   "double",  "1",  "Pack current from f_PackValuesP0 (A, discharge positive)"
       "iValid",  "boolean", "1",  "Current received and plausible"
       "tSensor", "double",  "26", "Temperatures from f_CellTemperatures (K)"
       "tValid",  "boolean", "26", "Not f_CellTemperatures invalid flag"
       "rtcNow",  "double",  "1",  "Pi clock (s, same epoch as nvmTSave)"
       "nvmSoc",  "double",  "13", "SOC record file: group SOC"
       "nvmTSave","double",  "1",  "SOC record file: save time (s)"
       "nvmValid","boolean", "1",  "SOC record file present and intact"
       "awake",   "boolean", "1",  "BMS frames arriving (BMS on)"
       "boot",    "boolean", "1",  "One step: first measurement set after the BMS came on"
       "reset",   "boolean", "1",  "One step: SOC to be re-initialised from OCV" };
for k = 1:size(in, 1)
    add_block("built-in/Inport", mdl + "/" + in{k,1}, "OutDataTypeStr", in{k,2}, "PortDimensions", in{k,3}, ...
        "SampleTime", "BMS_Ts", "Position", [40 40+60*k 70 54+60*k], "Description", in{k,4});
end
A = mdl + "/adapt";
add_block("built-in/SubSystem", A, "Position", [300 100 420 800]);
for k = 1:size(in, 1), add_block("built-in/Inport", A + "/" + in{k,1}, "Position", [40 40+60*k 70 54+60*k]); end
add_block("built-in/Outport", A + "/validData");  add_block("built-in/Outport", A + "/hw");  add_block("built-in/Outport", A + "/pwr");
for k = 1:size(in, 1), add_line(mdl, in{k,1} + "/1", "adapt/" + k); end

% validData: as the BMS's BMSVL output, built from the CAN values
B = @(lib, name, varargin) add_block(lib, A + "/" + name, varargin{:});
W = @(s, d) add_line(A, s, d, "autorouting", "on");
B("built-in/MinMax", "vMin", "Function", "min", "Inputs", "1");  W("vGroup/1", "vMin/1");
B("built-in/MinMax", "vMax", "Function", "max", "Inputs", "1");  W("vGroup/1", "vMax/1");
B("built-in/MinMax", "tMin", "Function", "min", "Inputs", "1");  W("tSensor/1", "tMin/1");
B("built-in/MinMax", "tMax", "Function", "max", "Inputs", "1");  W("tSensor/1", "tMax/1");
B("built-in/Logic", "allV", "Operator", "AND", "Inputs", "1");  W("vValid/1", "allV/1");
B("built-in/Logic", "allT", "Operator", "AND", "Inputs", "1");  W("tValid/1", "allT/1");
B("built-in/Logic", "allValid", "Operator", "AND", "Inputs", "3");
W("allV/1", "allValid/1");  W("iValid/1", "allValid/2");  W("allT/1", "allValid/3");
B("built-in/Constant", "noFb", "Value", "false", "OutDataTypeStr", "boolean");
B("built-in/Constant", "noIdx", "Value", "uint8(0)", "OutDataTypeStr", "uint8");
el = busElements("BMS_validData");
B("simulink/Signal Routing/Bus Creator", "validBus", "Inputs", string(numel(el)), "OutDataTypeStr", "Bus: BMS_validData");
src = struct("vGroup", "vGroup/1", "iPack", "iPack/1", "tSensor", "tSensor/1", "vMin", "vMin/1", "vMax", "vMax/1", ...
    "tMin", "tMin/1", "tMax", "tMax/1", "allValid", "allValid/1", "contactorFb", "noFb/1", "measReady", "awake/1", ...
    "vMinIdx", "noIdx/1", "vMaxIdx", "noIdx/1", "tMinIdx", "noIdx/1", "tMaxIdx", "noIdx/1");
for k = 1:numel(el), busIn(A, src.(el(k)), "validBus", k, el(k)); end
W("validBus/1", "validData/1");
% hw: Pi clock and the SOC record file; no buttons on the Pi
el = busElements("BMS_nvmRecord");
B("simulink/Signal Routing/Bus Creator", "nvmBus", "Inputs", string(numel(el)), "OutDataTypeStr", "Bus: BMS_nvmRecord");
src = struct("socGroup", "nvmSoc/1", "tSave", "nvmTSave/1", "valid", "nvmValid/1");
for k = 1:numel(el), busIn(A, src.(el(k)), "nvmBus", k, el(k)); end
B("built-in/Constant", "noBtn", "Value", "false", "OutDataTypeStr", "boolean");
el = busElements("BMS_hwIn");
B("simulink/Signal Routing/Bus Creator", "hwBus", "Inputs", string(numel(el)), "OutDataTypeStr", "Bus: BMS_hwIn");
src = struct("rtcNow", "rtcNow/1", "nvm", "nvmBus/1", "powerBtn", "noBtn/1", "resetBtn", "noBtn/1");
for k = 1:numel(el), busIn(A, src.(el(k)), "hwBus", k, el(k)); end
W("hwBus/1", "hw/1");
% pwr: from the BMS frames (awake / boot / reset decided by the Pi program)
el = busElements("BMS_pwrData");
B("simulink/Signal Routing/Bus Creator", "pwrBus", "Inputs", string(numel(el)), "OutDataTypeStr", "Bus: BMS_pwrData");
src = struct("awake", "awake/1", "boot", "boot/1", "reset", "reset/1", "powerOn", "noBtn/1", "powerOff", "noBtn/1");
for k = 1:numel(el), busIn(A, src.(el(k)), "pwrBus", k, el(k)); end
W("pwrBus/1", "pwr/1");

% ---- SE: copy of the BMS's state-estimation layer
load_system("bms");
add_block("bms/SE", mdl + "/SE", "Position", [520 300 660 500]);
set_param(mdl + "/SE", "RTWFcnName", "SE_Step");
add_line(mdl, "adapt/1", "SE/1", "autorouting", "on");  add_line(mdl, "adapt/2", "SE/2", "autorouting", "on");
add_line(mdl, "adapt/3", "SE/3", "autorouting", "on");
add_block("built-in/Outport", mdl + "/seData", "OutDataTypeStr", "Bus: BMS_seData", "Position", [760 390 790 404]);
add_line(mdl, "SE/1", "seData/1", "autorouting", "on");
save_system(mdl, fullfile(here, mdl + ".slx"));
fprintf("estimator.slx built\n");

function busIn(A, src, bc, k, name)
% bus element k of Bus Creator bc, via a Signal Conversion so the line carries the element name
    sc = A + "/" + bc + "_" + name;
    add_block("simulink/Signal Attributes/Signal Conversion", sc);
    add_line(A, src, bc + "_" + name + "/1", "autorouting", "on");
    l = add_line(A, bc + "_" + name + "/1", bc + "/" + k, "autorouting", "on");
    set_param(l, "Name", name);
end

function n = busElements(bus)
    b = getValue(getEntry(getSection(Simulink.data.dictionary.open("bms.sldd"), "Design Data"), bus));
    n = string({b.Elements.Name});
end
