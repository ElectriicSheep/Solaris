%% defineParameters.m
% Parameters and the configuration set (cfgHarness) for bmsPlatform.sldd.
% Safe to re-run: entries are overwritten; parameters of the previous (foxBMS-style) design
% are removed. Run after defineInterfaces.m. Re-run on a new machine: the custom-code paths
% for the BQ76952 emulator are absolute (project root).

dd  = Simulink.data.dictionary.open("bmsPlatform.sldd");
sec = getSection(dd, "Design Data");
root = currentProject().RootFolder;

% remove parameters of the previous design (archived on branch archive/foxbms-pi)
for e = find(sec, "DataSource", "bmsPlatform.sldd")'
    if ~isempty(regexp(e.Name, "^(SENS_|HW_|BMS_|CAN_|ARB_socTol)", "once")), deleteEntry(e); end
end

%       name                value    unit  description
p = { "LOAD_profile",       1,       "",   "Active load, selectable while running: 1 = CONST, 2 = PULSE, 3 = CYCLE A (loops), 4 = CYCLE A extended (loops); other = 0 A"
      "LOAD_iConst",        23.45,   "A",  "Constant discharge current (1C for one tube)"
      "LOAD_iPulse",        23.45,   "A",  "Pulse current"
      "LOAD_pulsePeriod",   600,     "s",  "Pulse period"
      "LOAD_pulseDuty",     50,      "",   "Pulse on-time, percent of period"
      "LOAD_scale",         1,       "",   "Scale factor on the CYCLE profiles"
      "PLANT_tAmbient",     288.15,  "K",  "Ambient temperature (match T0 in the battery params)"
      "PLANT_switchFault",  0,       "",   "Main switch fault injection, selectable while running: 0 = none, 1 = stuck open, 2 = welded (stuck closed); other = none"
      "AFE_Ts",             0.01,    "s",  "BQ76952 emulator step (= platform step): measurement and protection timing resolution"
      "AFE_vOffset",        zeros(13, 1), "V", "Offset added to each group voltage seen by the BQ76952 (fault injection, e.g. 0.6 V on one group to trip COV)"
      "AFE_tOffset",        zeros(7, 1),  "K", "Offset added to each thermistor temperature seen by the BQ76952 (fault injection)"
      "PI_link",            0,       "",   "Link to the Pi (variant, compile-time): 0 = none (advisory outputs not available), 1 = UDP SITL with the Pi at PI_host"
      "ADV_Ts",             0.1,     "s",  "Period of the advisory messages from the Pi"
      "ADV_tStale",         1,       "s",  "Advisory outputs stale if the ADV_Status heartbeat has not changed for this long" };
for k = 1:size(p, 1)
    s = Simulink.Parameter(p{k,2});
    s.Unit        = p{k,3};
    s.Description = p{k,4};
    putEntry(sec, p{k,1}, s);
end

% Thermistors (13. Pi/solaris_config.h): 7 on the BQ76952's multi-function pins. Thermistor k
% (k = 1-6) sits between the buried cells of the two groups of module k (cells 5 and 12 of the
% module); thermistor 7 on the buried cell of group 13 (cell 89). Cell numbering as the 91-element
% battery temperature output (module k occupies (k-1)*14 + 1..14). Pins in register order:
% CFETOFF DFETOFF ALERT TS1 TS2 TS3 HDQ DCHG DDSG; thermistors on TS1 TS3 HDQ DCHG DDSG CFETOFF
% DFETOFF (thermistor k -> pin thermPin(k)); ALERT and TS2 (wake / power button) read ambient.
thermPin = [4 6 7 8 9 1 2];                      % 1-based pin index for thermistors 1-7
M = zeros(9, 91);  bias = zeros(9, 1);
for k = 1:6, off = (k-1)*14;  M(thermPin(k), off + [5 12]) = 0.5; end
M(thermPin(7), 89) = 1;
unused = setdiff(1:9, thermPin);  bias(unused) = 298.15;
s = Simulink.Parameter(M);  s.Description = "BQ76952 pin temperatures from the 91 cell temperatures: tPin = AFE_thermMap * tCell + AFE_thermBias";
putEntry(sec, "AFE_thermMap", s);
s = Simulink.Parameter(bias);  s.Unit = "K";  s.Description = "Temperature of the pins without a thermistor (ALERT, TS2)";
putEntry(sec, "AFE_thermBias", s);
T = zeros(9, 7);  for k = 1:7, T(thermPin(k), k) = 1; end
s = Simulink.Parameter(T);  s.Description = "Thermistor k -> pin (for AFE_tOffset)";
putEntry(sec, "AFE_thermPins", s);

% Harness solver settings: fixed step, identical on desktop and on the OP5033 (RT-LAB needs a
% fixed step); the Simscape Solver Configuration in PLANT uses the same step.
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
set_param(cs, "DefaultParameterBehavior", "Tunable", ...
              "OptimizeBlockIOStorage",   "off", ...
              "BlockReduction",           "off");
set_param(cs, "UnderspecifiedInitializationDetection", "Simplified");
% BQ76952 emulator (12. AFE, C): compiled into the simulation and into generated code (RT-LAB)
afe = fullfile(root, "12. AFE");  pi = fullfile(root, "13. Pi");
inc = sprintf('"%s" "%s" "%s"', afe, pi, fullfile(pi, "libresolar"));
src = sprintf('"%s"', fullfile(afe, "bq76952_emul.c"));
set_param(cs, "SimCustomHeaderCode", '#include "bq76952_emul.h"', "SimUserIncludeDirs", inc, ...
              "SimUserSources", src, "SimCustomInitializer", "bqe_init();", ...
              "SimParseCustomCode", "on");
set_param(cs, "CustomHeaderCode", '#include "bq76952_emul.h"', "CustomInclude", inc, ...
              "CustomSource", src, "CustomInitializer", "bqe_init();");
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
