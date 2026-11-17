%% defineBMS.m
% Creates / updates the BMS's own data dictionary, bms.sldd (in 04. BMS):
%   - references bmsInterface.sldd (the contract: SENS_measBus in, BMS_outBus out)
%   - holds the BMS configuration cfgBMS (Embedded Coder, Raspberry Pi 4)
%   - holds the internal layer-to-layer buses (the BMS "database", as in foxBMS)
%   - holds the BMS parameters (the BMS's own knowledge of the cells)
%
% The BMS must NOT reference bmsPlatform.sldd: everything the generated BMS code
% needs comes from bms.sldd and the contract, so bms.slx builds on its own.
%
% Safe to re-run: entries are overwritten with the definitions below.

bmsFile = "bms.sldd";
ifcFile = "bmsInterface.sldd";
bmsDir  = fileparts(mfilename("fullpath"));     % 04. BMS

if isfile(fullfile(bmsDir, bmsFile))
    dd = Simulink.data.dictionary.open(fullfile(bmsDir, bmsFile));
else
    dd = Simulink.data.dictionary.create(fullfile(bmsDir, bmsFile));
end
if ~any(strcmp(dd.DataSources, ifcFile))
    addDataSource(dd, ifcFile);
end
assert(~any(strcmp(dd.DataSources, "bmsPlatform.sldd")), ...
    "bms.sldd must not reference the platform dictionary.");

%% Configuration: production-style C for the Raspberry Pi 4
cs = Simulink.ConfigSet;
cs.Name = "cfgBMS";
switchTarget(cs, "ert.tlc", []);                         % Embedded Coder
set_param(cs, ...
    "SolverType",  "Fixed-step", ...
    "Solver",      "FixedStepDiscrete", ...             % no continuous states in a BMS
    "FixedStep",   "0.01", ...                          % base rate 10 ms (= platform step)
    "StopTime",    "10", ...
    "EnableMultiTasking", "off", ...                    % one thread; 100 ms tasks run every 10th step
    "ProdHWDeviceType", "ARM Compatible->ARM 64-bit (LP64)", ...   % Pi 4: Cortex-A72, 64-bit Linux
    "ProdEqTarget", "on", ...
    "CodeInterfacePackaging", "Nonreusable function", ...
    "ModelReferenceNumInstancesAllowed", "Single", ...  % one BMS instance per tube controller
    "DefaultParameterBehavior", "Inlined", ...          % calibration values get explicit storage classes later
    "SupportContinuousTime", "off", ...
    "SupportNonFinite", "off", ...
    "MatFileLogging", "off", ...
    "GenCodeOnly", "on", ...                            % compile on the Pi later, with its own toolchain
    "GenerateReport", "on", ...
    "LaunchReport", "off", ...
    "GenerateComments", "on");
putEntry(getSection(dd, "Configurations"), bmsFile, "cfgBMS", cs);

%% Internal buses: one per layer output (never part of the contract)
nGroup = 13;  nTemp = 26;
secD = getSection(dd, "Design Data");
putBus(secD, bmsFile, "BMS_measData", "MEAS -> PLAUS: calibrated measurements", [ ...
    el("vGroup",  nGroup, "V", "double", "Calibrated group voltages")
    el("iPack",   1,      "A", "double", "Calibrated pack current, discharge positive")
    el("tSensor", nTemp,  "K", "double", "Calibrated temperatures")
    el("tsV",     1,      "s", "double", "Timestamp of the voltage sample")
    el("tsI",     1,      "s", "double", "Timestamp of the current sample")
    el("tsT",     1,      "s", "double", "Timestamp of the temperature sample")
    el("contactorFb", 1,  "",  "boolean", "Main contactor feedback: true = closed")
    el("tsC",     1,      "s", "double", "Timestamp of the contactor feedback sample")]);
putBus(secD, bmsFile, "BMS_plausData", "PLAUS -> BMSVL: measurements with per-channel validity", [ ...
    el("vGroup",  nGroup, "V", "double",  "Group voltages (as MEAS)")
    el("iPack",   1,      "A", "double",  "Pack current (as MEAS)")
    el("tSensor", nTemp,  "K", "double",  "Temperatures (as MEAS)")
    el("vValid",  nGroup, "",  "boolean", "Voltage channel plausible (range, staleness, rate)")
    el("iValid",  1,      "",  "boolean", "Current channel plausible")
    el("tValid",  nTemp,  "",  "boolean", "Temperature channel plausible")
    el("contactorFb", 1,  "",  "boolean", "Main contactor feedback (as MEAS)")
    el("cValid",  1,      "",  "boolean", "Contactor feedback plausible (e.g. not stale)")]);
putBus(secD, bmsFile, "BMS_validData", "BMSVL -> SOA, SE, BMS: validated values and extremes", [ ...
    el("vGroup",   nGroup, "V", "double",  "Validated group voltages")
    el("iPack",    1,      "A", "double",  "Validated pack current")
    el("tSensor",  nTemp,  "K", "double",  "Validated temperatures")
    el("vMin",     1,      "V", "double",  "Lowest valid group voltage")
    el("vMax",     1,      "V", "double",  "Highest valid group voltage")
    el("tMin",     1,      "K", "double",  "Lowest valid temperature")
    el("tMax",     1,      "K", "double",  "Highest valid temperature")
    el("allValid", 1,      "",  "boolean", "Every channel plausible")
    el("contactorFb", 1,   "",  "boolean", "Validated main contactor feedback: true = closed")]);
putBus(secD, bmsFile, "BMS_soaData", "SOA -> DIAG: limit violations, each [MOL RSL MSL]", [ ...
    el("overVoltage",      3, "", "boolean", "vMax above the limit [MOL RSL MSL]")
    el("underVoltage",     3, "", "boolean", "vMin below the limit [MOL RSL MSL]")
    el("overCurrentDchg",  3, "", "boolean", "Discharge current above the limit [MOL RSL MSL]")
    el("overCurrentChg",   3, "", "boolean", "Charge current above the limit [MOL RSL MSL]")
    el("overTemp",         3, "", "boolean", "tMax above the limit [MOL RSL MSL]")
    el("underTemp",        3, "", "boolean", "tMin below the limit [MOL RSL MSL]")]);
putBus(secD, bmsFile, "BMS_seData", "SE -> output: state estimates", [ ...
    el("socGroup", nGroup, "1", "double", "Estimated group SOC, 0-1")
    el("sohR",     nGroup, "1", "double", "Resistance SOH per group (1 = new)")
    el("sohQ",     nGroup, "1", "double", "Capacity SOH per group (1 = new)")
    el("socPack",  1,      "1", "double", "Pack SOC (minimum group SOC)")
    el("sohPack",  1,      "1", "double", "Pack SOH (worst group)")]);

%% BMS parameters
% PLACEHOLDERS: copied from the plant's nominal placeholder cell
% (bat_35E_13S7P_placeholder_params.m) so the BMS knows the NOMINAL cell exactly;
% the heterogeneous plant still differs from it per module (capacity, OCV offset, ...).
% Replace with the BMS's own characterisation data (HPPC / OCV tests) when available.
putParam(secD, bmsFile, "BMS_Ts", 0.1, "s", ...
    "BMS task period: the rate at which the BMS reads its inputs and runs MEAS..BMS " + ...
    "(must be a multiple of the 10 ms base rate in cfgBMS)");
putParam(secD, bmsFile, "BMS_Qnom", 7 * 3.35, "A*h", ...
    "Nominal (new) parallel-group capacity Q_nom: 7 cells x 3.35 Ah (placeholder). " + ...
    "Actual capacity per group Q_act = BMS_Qnom * SOH_Q, used by coulomb counting.");
old = find(secD, "Name", "BMS_Qgroup", "DataSource", bmsFile);    % renamed to BMS_Qnom
if ~isempty(old), deleteEntry(old); end
putParam(secD, bmsFile, "BMS_ocvSoc", 0:0.1:1, "1", ...
    "SOC breakpoints of the BMS OCV table (placeholder)");
putParam(secD, bmsFile, "BMS_ocvV", ...
    [2.650 3.380 3.510 3.590 3.655 3.725 3.795 3.875 3.970 4.075 4.200], "V", ...
    "Cell (= group) OCV at BMS_ocvSoc, strictly increasing (placeholder)");

% State machine (BMS layer). PLACEHOLDER times, to be set against the hardware
% (switch operating time, sensor rates) and the system safety requirements.
putParam(secD, bmsFile, "BMS_tInitSettle", 1, "s", ...
    "INITIALIZATION: start-up checks must pass continuously for this long before the switch is closed");
putParam(secD, bmsFile, "BMS_tInitMax", 10, "s", ...
    "INITIALIZATION: time allowed to pass the checks and close the switch before ERROR");
putParam(secD, bmsFile, "BMS_tCloseMax", 0.5, "s", ...
    "Time allowed for the switch feedback to confirm closed after the close command, before ERROR");
putParam(secD, bmsFile, "BMS_tRecover", 5, "s", ...
    "ERROR: fault conditions must be clear continuously for this long before a retry (back to INITIALIZATION)");
putParam(secD, bmsFile, "BMS_nRetryMax", 3, "", ...
    "Consecutive ERROR entries allowed before ERROR latches until power cycle");
putParam(secD, bmsFile, "BMS_tRetryReset", 60, "s", ...
    "Time in NORMAL after which the retry count is reset (a later fault counts as a new first fault)");

saveChanges(dd);
fprintf("bms.sldd written: references %s; configuration cfgBMS (%s, %s, %s s)\n", ...
    strjoin(string(dd.DataSources), ", "), get_param(cs, "SystemTargetFile"), ...
    get_param(cs, "Solver"), get_param(cs, "FixedStep"));

%% Local functions
function e = el(name, dims, unit, dataType, description)
    % One bus element
    e = Simulink.BusElement;
    e.Name = name;  e.Dimensions = dims;  e.DataType = dataType;
    e.Unit = unit;  e.Description = description;
end

function putBus(sec, ds, name, description, elements)
    % Create a bus object and store it in dictionary file ds
    b = Simulink.Bus;
    b.Description = description;
    b.Elements    = elements;
    putEntry(sec, ds, name, b);
end

function putParam(sec, ds, name, value, unit, description)
    % A Simulink.Parameter with unit and description
    p = Simulink.Parameter(value);
    p.Unit = unit;  p.Description = description;
    putEntry(sec, ds, name, p);
end

function putEntry(sec, ds, name, value)
    % Add the entry to dictionary file ds, or overwrite it if ds already holds it
    local = find(sec, "Name", name, "DataSource", ds);
    if ~isempty(local)
        setValue(local, value);
    else
        addEntry(sec, name, value);
    end
end
