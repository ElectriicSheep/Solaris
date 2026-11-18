%% defineInterfaces.m
% Defines the interfaces in two data dictionaries:
%
%   bmsInterface.sldd  - the BMS CONTRACT, the only types the BMS and the platform share:
%       SENS_measBus     measurements in   (SENS -> BMS; later the same content over CAN/UDP),
%                        including the contactor auxiliary-contact feedback
%       BMS_outBus       BMS outputs       (BMS -> PLANT contactor, EVAL, telemetry), containing
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
% Autonomous BMS: no external state requests. The main switch is open in
% INITIALIZATION until the start-up checks pass; the BMS then closes it itself and
% enters NORMAL once the switch feedback confirms it.
appendEnumeral(e, "INITIALIZATION", 0, "Switch open: start-up checks and SOC initialisation, then close and confirm");
appendEnumeral(e, "NORMAL",         1, "Switch closed: running and monitoring");
appendEnumeral(e, "ERROR",          2, "Switch open: fault; automatic retry after recovery, latched after the retry limit");
removeEnumeral(e, 1);                       % remove the default placeholder entry
e.DefaultValue = "INITIALIZATION";
e.Description  = "BMS system state";
putEntry(secIfc, ifcFile, "BMS_state", e);

% BMS event codes: what a log record (or an ERROR cause) is about. Groups of 16:
%   1-15 INFO events, 16-31 limit events (SOA/DIAG), 32-47 sensor validity,
%   48-63 causes of ERROR (state machine). The record's location field says WHERE
%   (group 1-13 for voltages, sensor 1-26 for temperatures, 0 = pack / not applicable).
c = Simulink.data.dictionary.EnumTypeDefinition;
codes = {
    "NONE",                       0, "No event (empty record slot / no ERROR cause)"
    "MEAS_READY",                 1, "Every sensor type has delivered its first sample"
    "START_CHECK_BEGIN",          2, "Start-up check begun (INITIALIZATION entered); location = attempt number"
    "START_CHECK_PASSED",         3, "Start-up check passed: main switch commanded closed"
    "SWITCH_CLOSED",              4, "Main switch closed and confirmed by feedback (NORMAL)"
    "STATE_CHANGE",               5, "BMS state changed; location = new state, value = previous state"
    "OVER_VOLTAGE",              16, "Group voltage above a limit; location = group"
    "UNDER_VOLTAGE",             17, "Group voltage below a limit; location = group"
    "OVER_CURRENT_DCHG",         18, "Discharge current above a limit"
    "OVER_CURRENT_CHG",          19, "Charge current above a limit"
    "OVER_TEMP",                 20, "Temperature above a limit; location = sensor"
    "UNDER_TEMP",                21, "Temperature below a limit; location = sensor"
    "SENSOR_V_INVALID",          32, "Voltage measurement implausible or stale; location = group (0 = several)"
    "SENSOR_I_INVALID",          33, "Current measurement implausible or stale"
    "SENSOR_T_INVALID",          34, "Temperature measurement implausible or stale; location = sensor (0 = several)"
    "SENSOR_C_INVALID",          35, "Main switch feedback stale"
    "DIAG_FAULT",                48, "ERROR cause: a debounced DIAG fault (details in the limit / sensor records)"
    "SWITCH_STUCK_OPEN",         49, "ERROR cause: switch commanded closed, feedback did not confirm within BMS_tCloseMax"
    "SWITCH_WELDED",             50, "ERROR cause: feedback reads closed while commanded open (start-up check never passed)"
    "SWITCH_OPENED_UNEXPECTEDLY",51, "ERROR cause: feedback opened in NORMAL without a DIAG fault"
    "INIT_TIMEOUT",              52, "ERROR cause: start-up check not passed within BMS_tInitMax"
    "RETRY_LIMIT",               53, "ERROR latched: BMS_nRetryMax consecutive errors (until power cycle)"};
for k = 1:size(codes, 1)
    appendEnumeral(c, codes{k,1}, codes{k,2}, codes{k,3});
end
removeEnumeral(c, 1);                       % remove the default placeholder entry
c.DefaultValue = "NONE";
c.StorageType  = "uint8";
c.Description  = "BMS event / fault code (category); see the enumeral descriptions";
putEntry(secIfc, ifcFile, "BMS_eventCode", c);

% No vehicle request: the BMS is autonomous (contactor open at start-up, closed by the
% BMS itself once its checks pass). Entries from the earlier request-based design are
% removed if present.
for n = ["VEH_requestBus" "BMS_request"]
    old = find(secIfc, "Name", n, "DataSource", ifcFile);
    if ~isempty(old), deleteEntry(old); end
end

% SENS_measBus
putBus(secIfc, ifcFile, "SENS_measBus", "Measurements into the BMS (contract)", [ ...
    el("vGroup",  nGroup, "V",    "double", "Measured group voltages")
    el("iPack",   1,      "A",    "double", "Measured pack current, discharge positive")
    el("tSensor", nTemp,  "K",    "double", "Measured temperatures: g1 buried, g1 outer, g2 buried, ...")
    el("tsV",     1,      "s",    "double", "Timestamp of the voltage sample")
    el("tsI",     1,      "s",    "double", "Timestamp of the current sample")
    el("tsT",     1,      "s",    "double", "Timestamp of the temperature sample")
    el("contactorFb", 1,  "",     "boolean", "Main contactor auxiliary contact: true = closed")
    el("tsC",     1,      "s",    "double", "Timestamp of the contactor feedback sample")]);

% DIAG_bus (first version; extended with the DIAG layer)
putBus(secIfc, ifcFile, "DIAG_bus", "Debounced fault flags from DIAG (contract)", [ ...
    el("overVoltage",   1, "", "boolean", "Group over-voltage fault")
    el("underVoltage",  1, "", "boolean", "Group under-voltage fault")
    el("overCurrent",   1, "", "boolean", "Pack over-current fault")
    el("overTemp",      1, "", "boolean", "Over-temperature fault")
    el("underTemp",     1, "", "boolean", "Under-temperature fault")
    el("sensorInvalid", 1, "", "boolean", "A measurement is out of range or stale")
    el("anyFatal",      1, "", "boolean", "At least one fatal fault present (debounced, not latched: latching and retries are done by the BMS state machine)")
    el("level",         6, "", "uint8",   "Debounced limit level per quantity [OV UV OCdchg OCchg OT UT]: 0 none, 1 MOL (MINOR), 2 RSL (MAJOR), 3 MSL (FAULT)")
    el("excursion",     6, "", "boolean", "MSL exceeded but cleared before BMS_tDiagSet (one-step pulse), same order as level")]);

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
    el("diag",     1,      "",     "Bus: DIAG_bus",   "Fault flags")
    el("contactorCmd", 1,  "",     "boolean",         "Main contactor command: true = close")
    el("errorCause",   1,  "",     "Enum: BMS_eventCode", "Why the BMS is in ERROR (NONE outside ERROR)")
    el("latched",      1,  "",     "boolean",         "ERROR latched after BMS_nRetryMax consecutive errors (until power cycle)")]);
saveChanges(ddIfc);

%% 2. Platform dictionary: reference the contract, keep only platform buses
ddPlat  = Simulink.data.dictionary.open(platFile);
secPlat = getSection(ddPlat, "Design Data");
for n = ["BMS_state" "BMS_eventCode" "SENS_measBus" "DIAG_bus" "BMS_outBus"]
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
    el("socCell",  nCell,  "1",    "double", "True cell SOC, 0-1")
    el("contactorClosed", 1, "",   "boolean", "True main contactor state: true = closed")]);
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
