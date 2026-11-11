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

% Harness solver settings (variable-step, for plant accuracy)
cs = Simulink.ConfigSet;
cs.Name = "cfgHarness";
set_param(cs, "SolverType", "Variable-step", "Solver", "daessc", ...
              "MaxStep", "0.1", "StopTime", "10");
putEntry(getSection(dd, "Configurations"), "cfgHarness", cs);

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