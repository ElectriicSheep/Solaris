%% defineInterfaces.m
% Defines the platform's interfaces in the data dictionary bmsPlatform.sldd:
%   BMS_state        enumeration of BMS system states
%   LOAD_bus         LOAD  -> PLANT
%   PLANT_truthBus   PLANT -> SENS, EVAL   (true values; never into the BMS)
%   SENS_measBus     SENS  -> BMS          (what the hardware would report)
%   DIAG_bus         fault flags (part of BMS_outBus)
%   BMS_outBus       BMS   -> EVAL, telemetry
%
% Safe to re-run: existing entries are overwritten with the definitions below.
% Afterwards, inspect them in the Type Editor / Bus Editor (open the dictionary).
%
% Conventions: SI units throughout, temperature in K (convert to degC only for display),
% current DISCHARGE POSITIVE, group 1 = slice 1 assembly 1 ... group 13 = half slice.

nGroup = 13;   % parallel groups in series
nCell  = 91;   % cells in one tube
nTemp  = 26;   % temperature sensors (2 per group)

dd  = Simulink.data.dictionary.open("bmsPlatform.sldd");
sec = getSection(dd, "Design Data");

%% BMS state enumeration
e = Simulink.data.dictionary.EnumTypeDefinition;
appendEnumeral(e, "UNINITIALIZED",  0, "Start-up");
appendEnumeral(e, "INITIALIZATION", 1, "Waiting for valid measurements and SOC initialisation");
appendEnumeral(e, "STANDBY",        2, "No load requested");
appendEnumeral(e, "NORMAL",         3, "Running");
appendEnumeral(e, "ERROR",          4, "Fatal fault latched");
removeEnumeral(e, 1);                       % remove the default placeholder entry
e.DefaultValue = "UNINITIALIZED";
e.Description  = "BMS system state";
putEntry(sec, "BMS_state", e);

%% LOAD_bus
putBus(sec, "LOAD_bus", "Load demand, LOAD -> PLANT", [ ...
    el("iDemand", 1, "A", "double", "Demanded pack current, discharge positive")]);

%% PLANT_truthBus
putBus(sec, "PLANT_truthBus", "True plant values, PLANT -> SENS and EVAL. Never into the BMS.", [ ...
    el("vGroup",   nGroup, "V",    "double", "True parallel-group voltages")
    el("socGroup", nGroup, "1",    "double", "True parallel-group SOC, 0-1")
    el("iPack",    1,      "A",    "double", "True pack current, sign as the plant current sensor")
    el("tCell",    nCell,  "K",    "double", "True cell temperatures, modules 1-7 in order")
    el("socCell",  nCell,  "1",    "double", "True cell SOC, 0-1")]);

%% SENS_measBus
putBus(sec, "SENS_measBus", "Measurements, SENS -> BMS", [ ...
    el("vGroup",  nGroup, "V",    "double", "Measured group voltages")
    el("iPack",   1,      "A",    "double", "Measured pack current, discharge positive")
    el("tSensor", nTemp,  "K",    "double", "Measured temperatures: g1 buried, g1 outer, g2 buried, ...")
    el("tsV",     1,      "s",    "double", "Timestamp of the voltage sample")
    el("tsI",     1,      "s",    "double", "Timestamp of the current sample")
    el("tsT",     1,      "s",    "double", "Timestamp of the temperature sample")]);

%% DIAG_bus (first version; extended in Step 5)
putBus(sec, "DIAG_bus", "Debounced fault flags from DIAG", [ ...
    el("overVoltage",   1, "", "boolean", "Group over-voltage fault")
    el("underVoltage",  1, "", "boolean", "Group under-voltage fault")
    el("overCurrent",   1, "", "boolean", "Pack over-current fault")
    el("overTemp",      1, "", "boolean", "Over-temperature fault")
    el("underTemp",     1, "", "boolean", "Under-temperature fault")
    el("sensorInvalid", 1, "", "boolean", "A measurement is out of range or stale")
    el("anyFatal",      1, "", "boolean", "At least one fatal fault is latched")]);

%% BMS_outBus
putBus(sec, "BMS_outBus", "BMS outputs, BMS -> EVAL and telemetry", [ ...
    el("socGroup", nGroup, "1",    "double",          "Estimated group SOC, 0-1")
    el("sohR",     nGroup, "1",    "double",          "Resistance state of health per group (1 = new)")
    el("sohQ",     nGroup, "1",    "double",          "Capacity state of health per group (1 = new)")
    el("socPack",  1,      "1",    "double",          "Pack SOC (minimum group SOC)")
    el("sohPack",  1,      "1",    "double",          "Pack SOH (worst group)")
    el("vMin",     1,      "V",    "double",          "Lowest validated group voltage")
    el("vMax",     1,      "V",    "double",          "Highest validated group voltage")
    el("tMax",     1,      "K",    "double",          "Highest validated temperature")
    el("state",    1,      "",     "Enum: BMS_state", "BMS system state")
    el("diag",     1,      "",     "Bus: DIAG_bus",   "Fault flags")]);

saveChanges(dd);
fprintf("Interfaces written to bmsPlatform.sldd:\n");
disp(string({find(sec).Name})');

%% Local functions
function e = el(name, dims, unit, dataType, description)
    % One bus element
    e = Simulink.BusElement;
    e.Name        = name;
    e.Dimensions  = dims;
    e.DataType    = dataType;
    e.Unit        = unit;
    e.Description = description;
end

function putBus(sec, name, description, elements)
    % Create a bus object and store it in the dictionary
    b = Simulink.Bus;
    b.Description = description;
    b.Elements    = elements;
    putEntry(sec, name, b);
end

function putEntry(sec, name, value)
    % Add the entry, or overwrite it if it already exists
    if exist(sec, name)
        setValue(getEntry(sec, name), value);
    else
        addEntry(sec, name, value);
    end
end
