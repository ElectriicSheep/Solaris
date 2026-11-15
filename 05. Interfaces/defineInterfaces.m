%% defineInterfaces.m
% Defines the interfaces in two data dictionaries:
%
%   bmsInterface.sldd  - the BMS CONTRACT, the only types the BMS and the platform share:
%       SENS_measBus     measurements in   (SENS -> BMS; later the same content over CAN/UDP)
%       BMS_outBus       BMS outputs       (BMS -> EVAL, telemetry), containing
%       DIAG_bus           fault flags
%       BMS_state          system state enumeration
%   bmsPlatform.sldd   - platform-only buses (never visible to the BMS):
%       LOAD_bus         LOAD  -> PLANT
%       PLANT_truthBus   PLANT -> SENS, EVAL (true values; never into the BMS)
%
% Dictionary references:  bms.sldd -> bmsInterface.sldd <- bmsPlatform.sldd
% so the BMS sees only the contract and its own data, and both sides use the same
% definitions of the shared types.
%
% Safe to re-run: entries are overwritten with the definitions below; contract types
% left over in bmsPlatform.sldd from earlier versions are removed (they now come from
% bmsInterface.sldd through the reference).
%
% Conventions: SI units throughout, temperature in K (convert to degC only for display),
% current DISCHARGE POSITIVE, group 1 = slice 1 assembly 1 ... group 13 = half slice.

nGroup = 13;   % parallel groups in series
nCell  = 91;   % cells in one tube
nTemp  = 26;   % temperature sensors (2 per group)

ifcFile  = "bmsInterface.sldd";
platFile = "bmsPlatform.sldd";
ifcDir   = fileparts(which(platFile));      % keep both dictionaries in 05. Interfaces

%% 1. Contract dictionary
if isfile(fullfile(ifcDir, ifcFile))
    ddIfc = Simulink.data.dictionary.open(fullfile(ifcDir, ifcFile));
else
    ddIfc = Simulink.data.dictionary.create(fullfile(ifcDir, ifcFile));
end
secIfc = getSection(ddIfc, "Design Data");

% BMS state enumeration
e = Simulink.data.dictionary.EnumTypeDefinition;
appendEnumeral(e, "UNINITIALIZED",  0, "Start-up");
appendEnumeral(e, "INITIALIZATION", 1, "Waiting for valid measurements and SOC initialisation");
appendEnumeral(e, "STANDBY",        2, "No load requested");
appendEnumeral(e, "NORMAL",         3, "Running");
appendEnumeral(e, "ERROR",          4, "Fatal fault latched");
removeEnumeral(e, 1);                       % remove the default placeholder entry
e.DefaultValue = "UNINITIALIZED";
e.Description  = "BMS system state";
putEntry(secIfc, ifcFile, "BMS_state", e);

% SENS_measBus
putBus(secIfc, ifcFile, "SENS_measBus", "Measurements into the BMS (contract)", [ ...
    el("vGroup",  nGroup, "V",    "double", "Measured group voltages")
    el("iPack",   1,      "A",    "double", "Measured pack current, discharge positive")
    el("tSensor", nTemp,  "K",    "double", "Measured temperatures: g1 buried, g1 outer, g2 buried, ...")
    el("tsV",     1,      "s",    "double", "Timestamp of the voltage sample")
    el("tsI",     1,      "s",    "double", "Timestamp of the current sample")
    el("tsT",     1,      "s",    "double", "Timestamp of the temperature sample")]);

% DIAG_bus (first version; extended with the DIAG layer)
putBus(secIfc, ifcFile, "DIAG_bus", "Debounced fault flags from DIAG (contract)", [ ...
    el("overVoltage",   1, "", "boolean", "Group over-voltage fault")
    el("underVoltage",  1, "", "boolean", "Group under-voltage fault")
    el("overCurrent",   1, "", "boolean", "Pack over-current fault")
    el("overTemp",      1, "", "boolean", "Over-temperature fault")
    el("underTemp",     1, "", "boolean", "Under-temperature fault")
    el("sensorInvalid", 1, "", "boolean", "A measurement is out of range or stale")
    el("anyFatal",      1, "", "boolean", "At least one fatal fault is latched")]);

% BMS_outBus
putBus(secIfc, ifcFile, "BMS_outBus", "BMS outputs (contract)", [ ...
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
saveChanges(ddIfc);

%% 2. Platform dictionary: reference the contract, keep only platform buses
ddPlat  = Simulink.data.dictionary.open(platFile);
secPlat = getSection(ddPlat, "Design Data");
for n = ["BMS_state" "SENS_measBus" "DIAG_bus" "BMS_outBus"]
    local = find(secPlat, "Name", n, "DataSource", platFile);
    if ~isempty(local), deleteEntry(local); end   % now supplied by bmsInterface.sldd
end
if ~any(strcmp(ddPlat.DataSources, ifcFile))
    addDataSource(ddPlat, ifcFile);
end

putBus(secPlat, platFile, "LOAD_bus", "Load demand, LOAD -> PLANT", [ ...
    el("iDemand", 1, "A", "double", "Demanded pack current, discharge positive")]);

putBus(secPlat, platFile, "PLANT_truthBus", "True plant values, PLANT -> SENS and EVAL. Never into the BMS.", [ ...
    el("vGroup",   nGroup, "V",    "double", "True parallel-group voltages")
    el("socGroup", nGroup, "1",    "double", "True parallel-group SOC, 0-1")
    el("iPack",    1,      "A",    "double", "True pack current, sign as the plant current sensor")
    el("tCell",    nCell,  "K",    "double", "True cell temperatures, modules 1-7 in order")
    el("socCell",  nCell,  "1",    "double", "True cell SOC, 0-1")]);
saveChanges(ddPlat);

fprintf("Contract in %s:\n", ifcFile);      disp(string({find(secIfc, "DataSource", ifcFile).Name})');
fprintf("Platform-only in %s:\n", platFile); disp(string({find(secPlat, "DataSource", platFile).Name})');
fprintf("%s references: %s\n", platFile, strjoin(string(ddPlat.DataSources), ", "));

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

function putBus(sec, ds, name, description, elements)
    % Create a bus object and store it in dictionary file ds
    b = Simulink.Bus;
    b.Description = description;
    b.Elements    = elements;
    putEntry(sec, ds, name, b);
end

function putEntry(sec, ds, name, value)
    % Add the entry to dictionary file ds, or overwrite it if ds already holds it
    % (entries reached only through a reference are left alone)
    local = find(sec, "Name", name, "DataSource", ds);
    if ~isempty(local)
        setValue(local, value);
    else
        addEntry(sec, name, value);
    end
end
