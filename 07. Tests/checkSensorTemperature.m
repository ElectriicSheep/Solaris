%% checkSensorTemperature.m
% Test for the SENS temperature chain (Step 4).
%
% Makes one cell hot (Module3, model cell 5, +5 K at start) so the 91 cell
% temperatures differ, then runs bmsTestPlatform twice for 300 s:
%   1. ideal sensors -> checks
%        - the battery's temperature order (the hot cell is element 33)
%        - the Selector picks the cells in sens.T_index
%        - the thermistor lag behaves as a first-order lag, time constant sens.T_tau
%        - sampling at sens.Ts_T and rounding to sens.T_lsb
%      by comparing every channel with a first-order lag computed here in
%      MATLAB from the logged true temperatures.
%   2. sensor errors -> offset per channel and noise level match sensor_params.m
%
% The hot cell is set only for these runs (Simulink.SimulationInput); the
% model itself is not changed.
%
% Before running, log two signals (right-click the line > Log Selected Signals):
%   - in PLANT: the line named tCell going into the truth Bus Creator
%   - in SENS:  the line named tSensor coming out of the temperature Quantizer

mdl   = "bmsTestPlatform";
tStop = 300;            % s; long enough for the lag and for noise statistics
dHot  = 5;              % K, initial excess of the hot cell
hotGlobal = 33;         % expected element of the 91 for Module3, model cell 5
load_system(mdl);

% Find Module3 inside the battery block (works through masks and links)
m3 = find_system(mdl + "/PLANT", "LookUnderMasks", "all", "FollowLinks", "on", ...
    "RegExp", "on", "Name", "^Module3$");
assert(isscalar(m3), "Could not find a single block named Module3 inside PLANT.");
hotExpr = sprintf("T0*ones(14,1) + %g*((1:14)'==5)", dHot);

in = Simulink.SimulationInput(mdl);
in = in.setModelParameter("StopTime", num2str(tStop));
in = in.setBlockParameter(m3{1}, "batteryTemperature", hotExpr);

%% Run 1: ideal sensors
SENS_enableErrors = 0;                                   %#ok<NASGU> read by sensor_params
out0 = sim(in);
[tT, uT] = getLoggedSignal(out0, "tCell",   "PLANT");    % 91 true temperatures
[tM, yM] = getLoggedSignal(out0, "tSensor", "SENS");     % 26 measured temperatures

% Battery temperature order: which of the 91 started hot?
[~, iHot] = max(uT(1,:));
chHot = find(sens.T_index == hotGlobal);
fprintf("\n=== Run 1: ideal sensors (%d samples x %d channels)\n", numel(tM), size(yM,2));
fprintf("Hot cell is element %d of 91 (expect %d) -> sensor channel %d\n", iHot, hotGlobal, chHot);
orderOK = iHot == hotGlobal;

% Expected sensor reading: first-order lag of the selected true temperatures,
% starting from the Integrator's initial condition T0
yExp  = lagModel(tT, uT(:, sens.T_index), sens.T_tau, T0, tM);
err0  = yM - yExp;
tol0  = sens.T_lsb/2 + 2e-3;                            % rounding + numerical margin
fprintf("Max |measured - expected| = %.3f K (limit %.3f K)\n", max(abs(err0(:))), tol0);
fprintf("Channel %d: true %.2f K at t=0; sensor %.2f K at t=0, %.2f K at t=%g s (lag model %.2f K)\n", ...
    chHot, uT(1,hotGlobal), yM(1,chHot), yM(tM==sens.T_tau, chHot), sens.T_tau, yExp(tM==sens.T_tau, chHot));
fprintf("Sample interval = %.3f s (expect %.3f s)\n", median(diff(tM)), sens.Ts_T);
pass1 = orderOK && max(abs(err0(:))) <= tol0 && abs(median(diff(tM)) - sens.Ts_T) < 1e-9;

%% Run 2: sensor errors on
SENS_enableErrors = 1;                                   %#ok<NASGU>
out1 = sim(in);
[tT, uT] = getLoggedSignal(out1, "tCell",   "PLANT");
[tM, yM] = getLoggedSignal(out1, "tSensor", "SENS");
yExp = lagModel(tT, uT(:, sens.T_index), sens.T_tau, T0, tM);
err1 = yM - yExp;

biasMeas  = mean(err1, 1)';
biasExp   = sens.T_offset;
noiseMeas = std(err1 - mean(err1, 1), 0, 1)';
noiseExp  = sqrt(sens.T_noiseVar + sens.T_lsb^2/12);
biasTol   = 4 * noiseExp / sqrt(size(err1,1)) + sens.T_lsb/2;

fprintf("\n=== Run 2: sensor errors on\n");
T = table((1:numel(biasMeas))', ceil((1:numel(biasMeas))'/2), biasExp, biasMeas, noiseMeas, ...
    'VariableNames', ["Channel","Group","OffsetExpected_K","OffsetMeasured_K","Noise_K"]);
disp(T)
fprintf("Noise expected %.3f K RMS per channel; measured %.3f to %.3f K\n", ...
    noiseExp, min(noiseMeas), max(noiseMeas));
fprintf("Offset tolerance per channel: +/-%.3f K\n", biasTol);
pass2 = all(abs(biasMeas - biasExp) <= biasTol) && ...
        all(abs(noiseMeas - noiseExp) <= 0.2*noiseExp);

%% Verdict
fprintf("\nRun 1 (order, selection, lag): %s\nRun 2 (errors):                %s\n", ...
    passFail(pass1), passFail(pass2));
clear SENS_enableErrors     % so sensor_params.m uses its own default again

%% Local functions
function y = lagModel(tU, u, tau, y0, tOut)
    % First-order lag dy/dt = (u - y)/tau, u linearly interpolated between
    % logged points, solved with ode45 and evaluated at tOut.
    nCh  = size(u, 2);
    f    = @(t, y) (interp1(tU, u, t).' - y) / tau;
    opts = odeset("RelTol", 1e-8, "AbsTol", 1e-6, "MaxStep", 0.5);
    sol  = ode45(f, [tU(1) tU(end)], y0 * ones(nCh,1), opts);
    y    = deval(sol, tOut).';
end

function s = passFail(ok)
    if ok, s = "PASS"; else, s = "FAIL"; end
end
