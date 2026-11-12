%% checkPlantHeatSpread.m
% Regression test for the cell-to-cell heat network in the PLANT (one-hot test).
%
% Runs bmsTestPlatform twice with zero load current for tStop seconds:
%   baseline : every cell starts at T0
%   hot      : as baseline, but Module3 model cell 5 (element 33 of 91) starts dHot warmer
% The thermal network is linear, so (hot - baseline) is the response to the hot
% cell alone; any other heat flow (ambient, tube air, hull) cancels out.
%
% Expected from the network files (cellPairs_2S7P.ssc, axialLink_2S7P.ssc):
%   1. the hot cell cools
%   2. its three in-slice neighbours (model cells 2, 3, 7 -> elements 30, 31, 35)
%      warm the most:     path R ~ 55-62 K/W each
%   3. the same-position cells of Module2 and Module4 (elements 19, 47) come next,
%      and warm by the same amount (symmetry):   path R = 180 K/W each
%   4. every other cell warms less than those, and Module1 and module_1S7P
%      (elements 1-14 and 85-91) hardly at all
%   5. no cell drops below its baseline (heat only flows from the hot cell)
% Runs with identical cells (PLANT_cellVariation = 0): with heterogeneous cells the
% Module2/Module4 symmetry check would not hold.
% These are ORDERING checks taken from the topology, not checks of the absolute
% values: the resistances are placeholders.
%
% Before running: tCell in PLANT must be logged (same as checkSensorTemperature.m).

mdl   = "bmsTestPlatform";
tStop = 120;      % s (ordering checks hold from ~60 s; 120 s keeps a margin)
dHot  = 10;       % K
hot   = 33;       % Module3, model cell 5
nbrIn = [30 31 35];
nbrAx = [19 47];
far   = [1:14 85:91];
load_system(mdl);

m3 = find_system(mdl, "MatchFilter", @Simulink.match.allVariants, "LookUnderMasks", "all", "FollowLinks", "on", ...
    "RegExp", "on", "Name", "^Module3$");
assert(isscalar(m3), "Could not find a single block named Module3 in the model.");

base = Simulink.SimulationInput(mdl);
base = base.setModelParameter("StopTime", num2str(tStop));
base = base.setVariable("LOAD_variant", 1);
base = base.setVariable("LOAD_iConst", 0);
hotIn = base.setBlockParameter(m3{1}, "batteryTemperature", ...
    sprintf("T0*ones(14,1) + %g*((1:14)'==5)", dHot));

SENS_enableErrors   = 0;                                 %#ok<NASGU> read by sensor_params
PLANT_cellVariation = 0;   %#ok<NASGU> identical cells: the symmetry check needs them (read by plant_params)
out0 = sim(base);
out1 = sim(hotIn);
clear SENS_enableErrors PLANT_cellVariation

[t0, T0log] = getLoggedSignal(out0, "tCell", "PLANT");
[t1, T1log] = getLoggedSignal(out1, "tCell", "PLANT");
dT = interp1(t1, T1log, t0) - T0log;      % response to the hot cell alone, 91 columns
dEnd = dT(end, :);

%% Report
fprintf("\n=== Heat spreading from element %d (+%g K), zero current, %g s\n", hot, dHot, tStop);
fprintf("Baseline drift (no hot cell): max |T - T(0)| = %.4f K\n", max(abs(T0log(end,:) - T0log(1,:))));
fprintf("Hot cell: +%.3f K at t=0 -> +%.3f K at t=%g s\n", dT(1,hot), dEnd(hot), tStop);
others = setdiff(1:91, hot);
[~, o] = sort(dEnd(others), "descend");
fprintf("Largest rises at t = %g s:\n", tStop);
for k = 1:8
    e = others(o(k));
    fprintf("  element %2d (module %d, cell %2d): %+.3f K\n", e, ceil(e/14), e - 14*(ceil(e/14)-1), dEnd(e));
end

%% Checks
rest = setdiff(others, [nbrIn nbrAx]);
c = struct();
c.hotCools      = dEnd(hot) < dT(1,hot);
c.inSliceFirst  = isequal(sort(others(o(1:3))), sort(nbrIn));
c.axialNext     = isequal(sort(others(o(4:5))), sort(nbrAx));
c.axialSymmetry = abs(dEnd(19) - dEnd(47)) < 0.05 * max(dEnd(nbrAx));
c.restBelow     = max(dEnd(rest)) < min(dEnd(nbrAx));
c.farSmall      = max(abs(dEnd(far))) < 0.01;
c.noneCooled    = min(dT(:, others), [], "all") > -1e-3;

names = string(fieldnames(c));
fprintf("\n");
for k = 1:numel(names)
    fprintf("  %-14s %s\n", names(k), passFail(c.(names(k))));
end
fprintf("\nOverall: %s\n", passFail(all(cell2mat(struct2cell(c)))));

function s = passFail(ok)
    if ok, s = "PASS"; else, s = "FAIL"; end
end
