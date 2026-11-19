%% defineInterfaces.m
% Bus definitions for the Solaris platform (bmsTestPlatform), in two dictionaries:
%   bmsInterface.sldd  contract with the Pi's advisory layer:
%       ADV_bus        advisory outputs decoded from the ADV_* CAN messages (10. CAN)
%   bmsPlatform.sldd   platform-only buses (references bmsInterface.sldd):
%       LOAD_bus        LOAD -> PLANT, AFE
%       PLANT_truthBus  PLANT -> AFE, EVAL (true values)
%       AFE_bus         AFE (BQ76952 emulator) -> EVAL: FETs and protection status
%       ARB_bus         ARB (vehicle-controller stand-in) -> EVAL
% Safe to re-run: every bus / enum stored by an earlier version of this script that is not
% defined below is removed (parameters are left to defineParameters.m).
% Conventions: SI units, temperature in K, current DISCHARGE POSITIVE (the BQ76952 itself
% reports charge positive; the AFE block and the Pi convert).

nGroup = 13;   % parallel groups in series
nCell  = 91;   % cells in one tube

ifcFile  = "bmsInterface.sldd";
platFile = "bmsPlatform.sldd";
ifcDir   = fileparts(which(platFile));

if isfile(fullfile(ifcDir, ifcFile))
    ddIfc = Simulink.data.dictionary.open(fullfile(ifcDir, ifcFile));
else
    ddIfc = Simulink.data.dictionary.create(fullfile(ifcDir, ifcFile));
end
secIfc = getSection(ddIfc, "Design Data");
ddPlat  = Simulink.data.dictionary.open(platFile);
secPlat = getSection(ddPlat, "Design Data");
if ~any(strcmp(ddPlat.DataSources, ifcFile)), addDataSource(ddPlat, ifcFile); end

%% 1. Contract with the Pi (bmsInterface.sldd)
purge(secIfc, ifcFile, "ADV_bus");
% NaN = not available (raw all-ones on CAN: that estimate is not produced yet).
putBus(secIfc, ifcFile, "ADV_bus", "Advisory outputs from the Pi, decoded from the ADV_* CAN messages (contract)", [ ...
    el("heartbeat",    1, "",   "double",  "ADV_Status heartbeat counter (0-255, wraps)")
    el("fresh",        1, "",   "boolean", "Heartbeat changed within ADV_tStale (link and Pi alive)")
    el("valid",        1, "",   "boolean", "Pi reports its estimates usable")
    el("socValid",     1, "",   "boolean", "SOC estimate usable")
    el("sohValid",     1, "",   "boolean", "SOH estimate usable")
    el("sopValid",     1, "",   "boolean", "SOP estimate usable")
    el("soeValid",     1, "",   "boolean", "SOE estimate usable")
    el("inputsStale",  1, "",   "boolean", "BQ76952 not answering the Pi")
    el("estimatorSet", 1, "",   "double",  "Estimator variant running on the Pi (0 = coulomb counting)")
    el("inputAge",     1, "s",  "double",  "Age of the BQ76952 measurement the Pi used")
    el("framesMissed", 1, "",   "double",  "Measurement cycles the Pi missed (wraps at 65536)")
    el("rxAge",        1, "s",  "double",  "Time since the last advisory datagram arrived")
    el("socMin",       1, "1",  "double",  "Lowest group SOC, 0-1")
    el("socMax",       1, "1",  "double",  "Highest group SOC, 0-1")
    el("socSigma",     1, "1",  "double",  "1-sigma SOC uncertainty, 0-1")
    el("sohQ",         1, "1",  "double",  "Capacity SOH, worst group (1 = new)")
    el("sohR",         1, "1",  "double",  "Resistance SOH Rnew/R, worst group (1 = new)")
    el("sopDchg",      1, "W",  "double",  "Discharge power available over the horizon")
    el("sopChg",       1, "W",  "double",  "Charge power available over the horizon")
    el("soeWh",        1, "Wh", "double",  "Remaining energy")
    el("soe",          1, "1",  "double",  "State of energy, 0-1")
    el("iDchgMax",     1, "A",  "double",  "Discharge current available over the horizon")
    el("iChgMax",      1, "A",  "double",  "Charge current available over the horizon")
    el("horizon",      1, "s",  "double",  "SOP prediction horizon")
    el("socGroup", nGroup, "1", "double",  "SOC per group, 0-1")
    el("afeState",     1, "",   "double",  "BQ76952 summary: bit0 CHG on, bit1 DSG on, bit2 safety fault, bit3 CONFIG_UPDATE")
    el("safetyA",      1, "",   "double",  "BQ76952 Safety Status A (bit2 CUV, 3 COV, 4 OCC, 5 OCD1, 6 OCD2, 7 SCD)")
    el("safetyB",      1, "",   "double",  "BQ76952 Safety Status B (bit0 UTC, 1 UTD, 4 OTC, 5 OTD)")
    el("safetyC",      1, "",   "double",  "BQ76952 Safety Status C")
    el("fetStatus",    1, "",   "double",  "BQ76952 FET Status (bit0 CHG, 2 DSG)")
    el("vStack",       1, "V",  "double",  "Stack voltage as measured by the BQ76952")
    el("iPack",        1, "A",  "double",  "Pack current as measured by the BQ76952, discharge positive")]);
saveChanges(ddIfc);

%% 2. Platform buses (bmsPlatform.sldd)
purge(secPlat, platFile, ["LOAD_bus" "PLANT_truthBus" "AFE_bus" "ARB_bus"]);
putBus(secPlat, platFile, "LOAD_bus", "Load demand, LOAD -> PLANT", [ ...
    el("iDemand", 1, "A", "double", "Demanded pack current, discharge positive")]);
putBus(secPlat, platFile, "PLANT_truthBus", "True plant values, PLANT -> AFE and EVAL", [ ...
    el("vGroup",   nGroup, "V",    "double", "True parallel-group voltages")
    el("socGroup", nGroup, "1",    "double", "True parallel-group SOC, 0-1")
    el("iPack",    1,      "A",    "double", "True pack current, discharge positive")
    el("tCell",    nCell,  "K",    "double", "True cell temperatures, modules 1-7 in order")
    el("socCell",  nCell,  "1",    "double", "True cell SOC, 0-1")
    el("contactorClosed", 1, "",   "boolean", "True main switch state: true = conducting")]);
putBus(secPlat, platFile, "AFE_bus", "BQ76952 emulator outputs, AFE -> EVAL", [ ...
    el("chg",       1, "",  "boolean", "CHG FET on")
    el("dsg",       1, "",  "boolean", "DSG FET on")
    el("safetyA",   1, "",  "uint8",   "Safety Status A (bit2 CUV, 3 COV, 4 OCC, 5 OCD1, 7 SCD)")
    el("safetyB",   1, "",  "uint8",   "Safety Status B (bit0 UTC, 1 UTD, 4 OTC, 5 OTD)")
    el("alertA",    1, "",  "uint8",   "Safety Alert A (condition present, delay running)")
    el("alertB",    1, "",  "uint8",   "Safety Alert B")
    el("conducting",1, "",  "boolean", "Main switch conducting for the demanded current direction (to PLANT)")]);
putBus(secPlat, platFile, "ARB_bus", "Arbitration (vehicle-controller stand-in): which SOC planning uses", [ ...
    el("useAdv",  1, "",  "boolean", "Advisory SOC used: fresh, valid and SOC valid")
    el("socPlan", 1, "1", "double",  "SOC for planning: advisory if useAdv, else NaN (the BQ76952 has no SOC)")]);
saveChanges(ddPlat);

fprintf("Contract in %s:\n", ifcFile);      disp(string({find(secIfc, "DataSource", ifcFile).Name})');
fprintf("Platform-only in %s:\n", platFile); disp(string({find(secPlat, "DataSource", platFile).Name})');

%% Local functions
function purge(sec, ds, keep)
    % remove buses / enums stored in ds by earlier versions (not parameters, not 'keep')
    for e = find(sec, "DataSource", ds)'
        v = getValue(e);
        if (isa(v, "Simulink.Bus") || isa(v, "Simulink.data.dictionary.EnumTypeDefinition")) && ~any(e.Name == keep)
            deleteEntry(e);
        end
    end
end
function e = el(name, dims, unit, dataType, description)
    e = Simulink.BusElement;
    e.Name = name;  e.Dimensions = dims;  e.DataType = dataType;  e.Unit = unit;  e.Description = description;
end
function putBus(sec, ds, name, description, elements)
    b = Simulink.Bus;  b.Description = description;  b.Elements = elements;
    putEntry(sec, ds, name, b);
end
function putEntry(sec, ds, name, value)
    x = find(sec, "Name", name, "DataSource", ds);
    if isempty(x), addEntry(sec, name, value); else, setValue(x, value); end
end
