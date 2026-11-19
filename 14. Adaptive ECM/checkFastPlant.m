function R = checkFastPlant(tStop)
%CHECKFASTPLANT Fast 13-group plant (ecmOffline/PLANT) vs the detailed 91-cell
% Simscape plant (bmsTestPlatform), driven by the same current.
%   1. Runs bmsTestPlatform for tStop s (default 600) on CYCLE A, Pi link off,
%      heterogeneous cells (PLANT_variationSeed 1).
%   2. Plays the detailed plant's true pack current into a copy of ecmOffline/PLANT
%      started from the detailed plant's group SOC and temperature.
%   3. Compares group voltages and SOC every 0.1 s. Pass: max |dV| <= 1 mV and
%      max |dSOC| <= 0.01 percentage points. Temperatures are reported only (the fast
%      plant has no cell-to-cell conduction).
if nargin < 1, tStop = 600; end
here = fileparts(mfilename("fullpath"));
work = fullfile(fileparts(here), "work");

%% 1. detailed plant
mdl = "bmsTestPlatform";
load_system(mdl);
in = Simulink.SimulationInput(mdl).setModelParameter("StopTime", string(tStop)) ...
    .setVariable("LOAD_profile", 3);
fprintf("Detailed plant: %g s simulated ... ", tStop);
tic; [~, out] = evalc("sim(in)"); fprintf("%.0f s wall\n", toc);
tr = out.logsout.get("truth").Values;
t  = tr.iPack.Time;  iP = tr.iPack.Data(:);
vD = rows(tr.vGroup);  zD = rows(tr.socGroup);  tC = rows(tr.tCell) - 273.15;
[t, iu] = unique(t, "last"); iP = iP(iu); vD = vD(iu, :); zD = zD(iu, :); tC = tC(iu, :);
save(fullfile(work, "checkFastPlant_detailed.mat"), "t", "iP", "vD", "zD", "tC");

%% 2. fast plant, same current
ECM = ecmParams();
ECM.plant.soc0 = zD(1, :)';
ECM.plant.T0C  = mean(tC(1, :));
assignin("base", "ECM", ECM);
h = "ecmPlantCheck";
if bdIsLoaded(h), close_system(h, 0); end
new_system(h);
load_system("ecmOffline");
add_block("ecmOffline/PLANT", h + "/PLANT");
set_param(h + "/PLANT/Iz", "InitialCondition", "ECM.plant.soc0(:)");
iTs = timeseries(iP, t);
assignin("base", "iCheck", iTs);
add_block("simulink/Sources/From Workspace", h + "/i", "VariableName", "iCheck", "Interpolate", "off", ...
    "OutputAfterFinalValue", "Holding final value");
add_line(h, "i/1", "PLANT/1");
nm = ["v" "z" "T"];
for k = 1:3
    add_block("simulink/Sinks/To Workspace", h + "/f_" + nm(k), "VariableName", "f_" + nm(k), ...
        "SaveFormat", "Array", "SampleTime", "ECM.Ts");
    add_line(h, "PLANT/" + k, "f_" + nm(k) + "/1");
end
for k = 4:7
    add_block("simulink/Sinks/Terminator", h + "/term" + k);
    add_line(h, "PLANT/" + k, "term" + k + "/1");
end
set_param(h, "SolverType", "Variable-step", "Solver", "ode45", "RelTol", "1e-6", "AbsTol", "1e-8", ...
    "MaxStep", "ECM.Ts", "StopTime", string(tStop), "ReturnWorkspaceOutputs", "on");
tic; o = sim(h); fprintf("Fast plant: %.1f s wall\n", toc);
close_system(h, 0);
tf = (0:size(o.f_v, 1)-1)' * ECM.Ts;

%% 3. compare on the fast plant's 0.1 s grid (detailed plant held at its last value)
vDi = interp1(t, vD, tf, "previous", "extrap");
zDi = interp1(t, zD, tf, "previous", "extrap");
% the current changes at the 0.1 s sample instants; compare just before each change
dV = abs(o.f_v(2:end, :) - vDi(2:end, :));
dZ = abs(o.f_z(2:end, :) - zDi(2:end, :));
R.maxdV_mV = max(dV, [], "all") * 1e3;
R.maxdSoc_pp = max(dZ, [], "all") * 100;
R.rmsdV_mV = sqrt(mean(dV.^2, "all")) * 1e3;
tCg = groupMean(tC);
tCgi = interp1(t, tCg, tf, "previous", "extrap");
R.maxdT_K = max(abs(o.f_T - tCgi), [], "all");
R.pass = R.maxdV_mV <= 1 && R.maxdSoc_pp <= 0.01;
fprintf("Group voltage: max |dV| %.3f mV, rms %.3f mV (limit 1 mV)\n", R.maxdV_mV, R.rmsdV_mV);
fprintf("Group SOC: max |dSOC| %.4f percentage points (limit 0.01)\n", R.maxdSoc_pp);
fprintf("Temperature (report only): max |dT| %.2f K vs the mean of each group's cells\n", R.maxdT_K);
fprintf("Overall: %s\n", string(ifelse(R.pass, "PASS", "FAIL")));
end

function d = rows(ts)
d = squeeze(ts.Data);
if size(d, 1) ~= numel(ts.Time), d = d.'; end
end

function g = groupMean(tC)
% cells are listed module by module (14 per 2S7P module, 7 in the last); 7 per group
g = zeros(size(tC, 1), 13);
for k = 1:13, g(:, k) = mean(tC(:, (k-1)*7 + (1:7)), 2); end
end

function y = ifelse(c, a, b)
if c, y = a; else, y = b; end
end
