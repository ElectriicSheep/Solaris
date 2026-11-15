%% defineBMS.m
% Creates / updates the BMS's own data dictionary, bms.sldd (in 04. BMS):
%   - references bmsInterface.sldd (the contract: SENS_measBus in, BMS_outBus out)
%   - holds the BMS configuration cfgBMS (Embedded Coder, Raspberry Pi 4)
%   - will hold the BMS parameters and internal (layer-to-layer) buses
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

saveChanges(dd);
fprintf("bms.sldd written: references %s; configuration cfgBMS (%s, %s, %s s)\n", ...
    strjoin(string(dd.DataSources), ", "), get_param(cs, "SystemTargetFile"), ...
    get_param(cs, "Solver"), get_param(cs, "FixedStep"));

%% Local functions
function putEntry(sec, ds, name, value)
    % Add the entry to dictionary file ds, or overwrite it if ds already holds it
    local = find(sec, "Name", name, "DataSource", ds);
    if ~isempty(local)
        setValue(local, value);
    else
        addEntry(sec, name, value);
    end
end
