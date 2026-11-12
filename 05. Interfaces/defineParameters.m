%% defineParameters.m
% Parameters and configuration sets for bmsPlatform.sldd.
% Safe to re-run: existing entries are overwritten with these values.
% Run after defineInterfaces.m when (re)creating the dictionary.

dd  = Simulink.data.dictionary.open("bmsPlatform.sldd");
sec = getSection(dd, "Design Data");

%       name                value    unit  description
p = { "LOAD_variant",       1,       "",   "Active load: 1 = CONST, 2 = PULSE, 3 = CYCLE"
      "LOAD_iConst",        23.45,   "A",  "Constant discharge current (1C for one tube)"
      "LOAD_iPulse",        23.45,   "A",  "Pulse current"
      "LOAD_pulsePeriod",   600,     "s",  "Pulse period"
      "LOAD_pulseDuty",     50,      "",   "Pulse on-time, percent of period"
      "LOAD_scale",         1,       "",   "Scale factor on the mission profile"
      "PLANT_tAmbient",     288.15,  "K",  "Ambient temperature (match T0 in the battery params)" };

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
putEntry(cfgSec, "cfgHarness", cs);

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