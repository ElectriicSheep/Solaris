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
    "GenerateComments", "on", ...
    "UnderspecifiedInitializationDetection", "Simplified");   % must match the platform (cfgHarness)
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
    el("cValid",  1,      "",  "boolean", "Contactor feedback plausible (e.g. not stale)")
    el("measReady", 1,    "",  "boolean", "Every sensor type has delivered a new sample since start-up (latched)")]);
putBus(secD, bmsFile, "BMS_validData", "BMSVL -> SOA, SE, BMS: validated values and extremes", [ ...
    el("vGroup",   nGroup, "V", "double",  "Validated group voltages")
    el("iPack",    1,      "A", "double",  "Validated pack current")
    el("tSensor",  nTemp,  "K", "double",  "Validated temperatures")
    el("vMin",     1,      "V", "double",  "Lowest VALID group voltage (last valid value held if none valid)")
    el("vMax",     1,      "V", "double",  "Highest VALID group voltage (last valid value held if none valid)")
    el("tMin",     1,      "K", "double",  "Lowest VALID temperature (last valid value held if none valid)")
    el("tMax",     1,      "K", "double",  "Highest VALID temperature (last valid value held if none valid)")
    el("allValid", 1,      "",  "boolean", "Every channel plausible")
    el("contactorFb", 1,   "",  "boolean", "Validated main contactor feedback: true = closed")
    el("measReady", 1,     "",  "boolean", "Every sensor type has delivered a new sample since start-up (latched)")
    el("vMinIdx",  1,      "",  "uint8",   "Group (1-13) with the lowest valid voltage; 0 = none valid yet")
    el("vMaxIdx",  1,      "",  "uint8",   "Group (1-13) with the highest valid voltage; 0 = none valid yet")
    el("tMinIdx",  1,      "",  "uint8",   "Sensor (1-26) with the lowest valid temperature; 0 = none valid yet")
    el("tMaxIdx",  1,      "",  "uint8",   "Sensor (1-26) with the highest valid temperature; 0 = none valid yet")]);
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
    el("sohPack",  1,      "1", "double", "Pack SOH (worst group)")
    el("socInitMethod",   1, "",  "uint8",   "How SOC was initialised: 0 not yet, 1 stored, 2 stored/OCV blend, 3 OCV")
    el("socInitMismatch", 1, "",  "boolean", "Stored SOC disagreed with OCV beyond BMS_socMismatchTol (OCV used)")
    el("socInitDiff",     1, "1", "double",  "Largest |stored - OCV| SOC difference over the groups at initialisation")
    el("socInitDiffIdx",  1, "",  "uint8",   "Group (1-13) with that largest difference; 0 = not evaluated")
    el("socInitRest",     1, "s", "double",  "Rest time since the stored record was saved (rtcNow - tSave)")
    el("nvm",             1, "",  "Bus: BMS_nvmRecord", "Record to save (current SOC, time, valid once SOC is initialised)")]);

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

% SOC start-up initialisation (SE). PLACEHOLDERS: relaxation time depends on chemistry
% (NMC ~2 h to 98 % of the steady-state OCV, NCA slower: Theuerkauf & Swan 2022); confirm
% the 35E chemistry and measure it on real cells.
putParam(secD, bmsFile, "BMS_tRelax", 7200, "s", ...
    "Rest time after which the OCV is fully trusted at start-up (shorter rests blend stored SOC and OCV linearly)");
putParam(secD, bmsFile, "BMS_socMismatchTol", 0.10, "1", ...
    "Largest stored-vs-OCV SOC difference explained by OCV error; beyond it the battery is taken as recharged or swapped while off and OCV is used");

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

% PLAUS: plausibility (sensor-fault) ranges and staleness. PLACEHOLDERS: set from the
% chosen sensors' ranges and the hardware's sample periods.
putParam(secD, bmsFile, "BMS_vPlausRange", [1.0 4.5], "V", ...
    "Plausible group-voltage range [min max]; outside = sensor fault (cell limits are SOA's)");
putParam(secD, bmsFile, "BMS_iPlausMax", 200, "A", ...
    "Largest plausible |pack current| (current-sensor range)");
putParam(secD, bmsFile, "BMS_tPlausRange", [233.15 373.15], "K", ...
    "Plausible temperature range [min max] (-40 to 100 degC)");
putParam(secD, bmsFile, "BMS_tStale", [0.3 0.3 3.0 0.3], "s", ...
    "Longest time each timestamp [V I T C] may stay unchanged before the channel is stale " + ...
    "(3 x the hardware sample period: 0.1, 0.1, 1.0, 0.1 s)");

% SOA: limits per quantity as [MOL RSL MSL]. MSLs from the Samsung INR18650-35E
% product specification (Ver. 1.1), scaled to a 7P group, EXCEPT the over-voltage MSL:
% 4.20 V is the charge (CV) set point, reached in normal use, so the MSL is set above it
% (4.25 V, engineering judgement, as protection ICs for 4.2 V cells are set above the
% charge voltage). MOL and RSL margins are placeholders.
lim.vMax     = [4.21 4.23 4.25];               % V   (charge voltage 4.20 V)
lim.vMin     = [3.00 2.80 2.65];               % V   (discharge cut-off 2.65 V)
lim.iDchg    = [45 50 56];                     % A   (7 x 8 A max continuous discharge)
lim.iChg     = [11.9 12.6 14];                 % A   (7 x 1.7 A standard, 7 x 2.0 A max charge)
lim.tMaxDchg = [50 55 60]   + 273.15;          % K   (discharge -10 to 60 degC)
lim.tMinDchg = [0 -5 -10]   + 273.15;
lim.tMaxChg  = [35 40 45]   + 273.15;          % K   (charge 0 to 45 degC)
lim.tMinChg  = [10 5 0]     + 273.15;
putParam(secD, bmsFile, "BMS_soaLim", lim, "", ...
    "SOA limits, each [MOL RSL MSL]: vMax vMin (V), iDchg iChg (A), tMaxDchg tMinDchg tMaxChg tMinChg (K)");
putParam(secD, bmsFile, "BMS_iRest", 0.2, "A", ...
    "Current magnitude below which the pack is not charging/discharging (foxBMS default 200 mA)");

% DIAG: debounce times. PLACEHOLDERS.
putParam(secD, bmsFile, "BMS_tDiagSet", 0.5, "s", ...
    "A limit violation or implausible measurement must persist this long to set its fault");
putParam(secD, bmsFile, "BMS_tDiagClear", 1.0, "s", ...
    "A fault clears after its violation has been absent this long");

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
