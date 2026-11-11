%% checkSensorVoltage.m
% Test for the SENS voltage chain (Step 4).
%
% Runs bmsTestPlatform twice for 60 s:
%   1. ideal sensors  -> measured = true group voltage at each 0.1 s sample,
%                        to within half a quantisation step
%   2. sensor errors  -> per-channel bias matches the configured offset and
%                        gain error; noise level matches the configured variance
%
% Before running, log two signals (right-click the line > Log Selected Signals):
%   - in PLANT: the line named vGroup going into the truth Bus Creator
%   - in SENS:  the line named vGroup coming out of the Quantizer
%
% Expected numbers come from sensor_params.m, so this test stays valid if the
% placeholder values are replaced with datasheet values.

mdl   = "bmsTestPlatform";
tStop = "60";
load_system(mdl);

%% Run 1: ideal sensors
SENS_enableErrors = 0;                                   %#ok<NASGU> read by sensor_params
out0 = sim(mdl, "StopTime", tStop);
[tT, vT] = getLoggedSignal(out0, "vGroup", "PLANT");
[tM, vM] = getLoggedSignal(out0, "vGroup", "SENS");
vTk  = interp1(tT, vT, tM);                              % truth at the sample instants
err0 = vM - vTk;
tol0 = sens.V_lsb/2 + 1e-9;

fprintf("\n=== Run 1: ideal sensors (%d samples x %d channels)\n", size(vM,1), size(vM,2));
fprintf("Max |measured - true| = %.1f uV (limit %.1f uV, half a quantisation step)\n", ...
    1e6*max(abs(err0(:))), 1e6*tol0);
fprintf("Sample interval = %.3f s (expect %.3f s)\n", median(diff(tM)), sens.Ts_V);
pass1 = max(abs(err0(:))) <= tol0 && abs(median(diff(tM)) - sens.Ts_V) < 1e-9;

%% Run 2: sensor errors on
SENS_enableErrors = 1;                                   %#ok<NASGU>
out1 = sim(mdl, "StopTime", tStop);
[tT, vT] = getLoggedSignal(out1, "vGroup", "PLANT");
[tM, vM] = getLoggedSignal(out1, "vGroup", "SENS");
vTk  = interp1(tT, vT, tM);
err1 = vM - vTk;

biasMeas = mean(err1, 1)';                                % measured bias per channel
biasExp  = sens.V_offset + (sens.V_gain - 1) .* mean(vTk, 1)';   % offset + gain error
noiseMeas = std(err1 - mean(err1, 1), 0, 1)';            % noise per channel
noiseExp  = sqrt(sens.V_noiseVar + sens.V_lsb^2/12);      % noise + quantisation
biasTol   = 4 * noiseExp / sqrt(size(err1,1)) + sens.V_lsb/2;   % 4 standard errors + rounding

T = table((1:numel(biasMeas))', 1e3*biasExp, 1e3*biasMeas, 1e3*noiseMeas, ...
    'VariableNames', ["Group","BiasExpected_mV","BiasMeasured_mV","Noise_mV"]);
fprintf("\n=== Run 2: sensor errors on\n");
disp(T)
fprintf("Noise expected %.3f mV RMS per channel; measured %.3f to %.3f mV\n", ...
    1e3*noiseExp, 1e3*min(noiseMeas), 1e3*max(noiseMeas));
fprintf("Bias tolerance per channel: +/-%.3f mV\n", 1e3*biasTol);
pass2 = all(abs(biasMeas - biasExp) <= biasTol) && ...
        all(abs(noiseMeas - noiseExp) <= 0.15*noiseExp);

%% Verdict
fprintf("\nRun 1 (ideal):  %s\nRun 2 (errors): %s\n", passFail(pass1), passFail(pass2));
clear SENS_enableErrors     % so sensor_params.m uses its own default again

function s = passFail(ok)
    if ok, s = "PASS"; else, s = "FAIL"; end
end
