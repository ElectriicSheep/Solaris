%% checkSensorCurrent.m
% Test for the SENS current chain (Step 4).
%
% Uses the CONST load (discharge at LOAD_iConst) and runs bmsTestPlatform
% twice for 60 s:
%   1. ideal sensors  -> measured current = true current at each sample, with
%                        DISCHARGE POSITIVE (checks sens.I_sign), to within
%                        half a quantisation step
%   2. sensor errors  -> bias matches the configured offset and gain error;
%                        noise matches the configured variance
% It also prints what the configured errors mean for coulomb counting.
%
% Before running, log two signals (right-click the line > Log Selected Signals):
%   - in PLANT: the line named iPack going into the truth Bus Creator
%   - in SENS:  the line named iPack coming out of the current Quantizer
%
% Expected numbers come from sensor_params.m and the dictionary.

mdl   = "bmsTestPlatform";
tStop = "60";
load_system(mdl);

% The test needs the constant discharge load
dd = Simulink.data.dictionary.open("bmsPlatform.sldd");
dsec = getSection(dd, "Design Data");
loadProfile = getValue(getEntry(dsec, "LOAD_profile"));
iConst      = getValue(getEntry(dsec, "LOAD_iConst"));
assert(loadProfile.Value == 1, "Set LOAD_profile = 1 (CONST) in the dictionary first.");
iConst = iConst.Value;

%% Run 1: ideal sensors
SENS_enableErrors = 0;                                   %#ok<NASGU> read by sensor_params
out0 = sim(mdl, "StopTime", tStop);
[tT, iT] = getLoggedSignal(out0, "iPack", "PLANT");
[tM, iM] = getLoggedSignal(out0, "iPack", "SENS");
iTk  = interp1(tT, iT, tM);                              % truth at the sample instants
err0 = iM - sens.I_sign * iTk;
tol0 = sens.I_lsb/2 + 1e-9;

fprintf("\n=== Run 1: ideal sensors (%d samples)\n", numel(tM));
fprintf("Plant current reads %+.3f A; measured current reads %+.3f A (expect +%.2f A, discharge positive)\n", ...
    mean(iTk), mean(iM), iConst);
fprintf("Max |measured - true| = %.2f mA (limit %.2f mA, half a quantisation step)\n", ...
    1e3*max(abs(err0)), 1e3*tol0);
signOK = abs(mean(iM) - iConst) < 0.01*iConst;
if ~signOK && abs(mean(iM) + iConst) < 0.01*iConst
    fprintf("SIGN IS WRONG: set sens.I_sign = %d in sensor_params.m\n", -sens.I_sign);
end
pass1 = signOK && max(abs(err0)) <= tol0 && abs(median(diff(tM)) - sens.Ts_I) < 1e-9;

%% Run 2: sensor errors on
SENS_enableErrors = 1;                                   %#ok<NASGU>
out1 = sim(mdl, "StopTime", tStop);
[tT, iT] = getLoggedSignal(out1, "iPack", "PLANT");
[tM, iM] = getLoggedSignal(out1, "iPack", "SENS");
iTk  = sens.I_sign * interp1(tT, iT, tM);                % true current, discharge positive
err1 = iM - iTk;

biasMeas  = mean(err1);
biasExp   = sens.I_offset + (sens.I_gain - 1) * mean(iTk);
noiseMeas = std(err1 - biasMeas);
noiseExp  = sqrt(sens.I_noiseVar + sens.I_lsb^2/12);
biasTol   = 4 * noiseExp / sqrt(numel(err1)) + sens.I_lsb/2;

fprintf("\n=== Run 2: sensor errors on\n");
fprintf("Bias:  expected %.2f mA, measured %.2f mA (tolerance +/-%.2f mA)\n", ...
    1e3*biasExp, 1e3*biasMeas, 1e3*biasTol);
fprintf("Noise: expected %.2f mA RMS, measured %.2f mA RMS\n", 1e3*noiseExp, 1e3*noiseMeas);
pass2 = abs(biasMeas - biasExp) <= biasTol && abs(noiseMeas - noiseExp) <= 0.15*noiseExp;

%% What the configured errors mean for coulomb counting
Q = 7 * 3.35;                                            % tube capacity, A*h (placeholder cell)
fprintf("\n=== Effect on coulomb counting (capacity %.2f A*h)\n", Q);
fprintf("Offset %.0f mA -> SOC drift of %.3f %% per hour, %.2f %% over 10 h\n", ...
    1e3*sens.I_offset, 100*sens.I_offset/Q, 1000*sens.I_offset/Q);
fprintf("Gain error %.2f %% -> every SOC change scaled by %.2f %%\n", ...
    100*(sens.I_gain-1), 100*(sens.I_gain-1));

%% Verdict
fprintf("\nRun 1 (ideal, sign): %s\nRun 2 (errors):      %s\n", passFail(pass1), passFail(pass2));
clear SENS_enableErrors     % so sensor_params.m uses its own default again

function s = passFail(ok)
    if ok, s = "PASS"; else, s = "FAIL"; end
end
