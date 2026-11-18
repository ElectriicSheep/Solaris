%% checkBmsSocInit.m
% Tests the BMS start-up SOC initialisation (SE, socEstimate.m): stored record from the
% previous power cycle (HW_nvm) cross-checked against OCV, weighted by rest time.
% Each scenario is one power-up: plant SOC SOC0, stored record HW_nvm, real-time clock
% HW_rtcStart (rest = HW_rtcStart - HW_nvm.tSave). No load, sensor errors on, 4 s.
%
%   1 short rest (10 min), record correct            -> method 2 (blend), SOC within 1 %
%   2 long rest (4 h), record correct                -> method 3 (OCV),   SOC within 1 %
%   3 recharged while off: true 100 %, record 40 %  -> mismatch flagged (MINOR SOC_MISMATCH),
%                                                      method 3 (OCV),   SOC within 1 %
%   4 no valid record (first power-up)               -> method 3 (OCV),   SOC within 1 %
%   5 short rest, record 5 % too high (not a mismatch) -> method 2: the stored error is
%     mostly kept (w = rest/BMS_tRelax): checks SOC = w*OCV + (1-w)*stored, within 0.5 %
% Limitation: the plant has no voltage relaxation after load (it starts at rest), so
% these runs show the decision logic and the blending, not the effect of short rests
% on OCV accuracy; that needs measured relaxation data.

runCheck();

function runCheck()
    mdl = "bmsTestPlatform";  load_system(mdl);
    s = getSection(Simulink.data.dictionary.open("bms.sldd"), "Design Data");
    tRelax = getValue(getEntry(s, "BMS_tRelax")).Value;
    rtc = 1e6;  nG = 13;
    rec = @(soc, rest, valid) struct("socGroup", soc*ones(nG,1), "tSave", rtc - rest, "valid", valid);
    S = struct("name", {}, "soc0", {}, "nvm", {}, "method", {}, "mismatch", {}, "tol", {}, "expect", {});
    S(end+1) = struct("name", "short rest (10 min), record correct", "soc0", 0.6, "nvm", rec(0.6, 600, true), ...
        "method", 2, "mismatch", false, "tol", 0.01, "expect", NaN);
    S(end+1) = struct("name", "long rest (4 h), record correct", "soc0", 0.6, "nvm", rec(0.6, 4*3600, true), ...
        "method", 3, "mismatch", false, "tol", 0.01, "expect", NaN);
    S(end+1) = struct("name", "recharged while off (true 100 %, record 40 %)", "soc0", 1.0, "nvm", rec(0.4, 1800, true), ...
        "method", 3, "mismatch", true, "tol", 0.01, "expect", NaN);
    S(end+1) = struct("name", "no valid record (first power-up)", "soc0", 0.6, "nvm", rec(0, 0, false), ...
        "method", 3, "mismatch", false, "tol", 0.01, "expect", NaN);
    w = 600 / tRelax;
    S(end+1) = struct("name", "short rest, record 5 % too high", "soc0", 0.6, "nvm", rec(0.65, 600, true), ...
        "method", 2, "mismatch", false, "tol", 0.005, "expect", w*0.6 + (1-w)*0.65);

    pass = true(1, numel(S));
    for k = 1:numel(S)
        in = Simulink.SimulationInput(mdl).setModelParameter("StopTime", "4") ...
            .setVariable("LOAD_profile", 0).setVariable("SOC0", S(k).soc0) ...
            .setVariable("HW_nvm", S(k).nvm).setVariable("HW_rtcStart", rtc);
        [~, out] = evalc("sim(in)");
        fprintf("\n=== %d. %s\n", k, S(k).name);
        T = printBmsLog(out, true);
        for j = find(T.faultCode == "SOC" | startsWith(T.faultCode, "SOC-MIS"))'
            fprintf("   %6.2f s  %-5s %-14s %s\n", T.t(j), T.severity(j), T.faultCode(j), T.text(j));
        end
        [~, sT] = getLoggedSignal(out, "socTrue", "EVAL");  [~, sB] = getLoggedSignal(out, "socBms", "EVAL");
        m = T.location(T.faultCode == "SOC");  mis = any(startsWith(T.faultCode, "SOC-MIS"));
        ref = sT(end, :);  if ~isnan(S(k).expect), ref = S(k).expect * ones(1, nG); end
        err = max(abs(sB(end, :) - ref));
        fprintf("   method %d (expected %d), mismatch %d (expected %d), max |SOC_BMS - %s| = %.2f %% (limit %.1f %%)\n", ...
            m, S(k).method, mis, S(k).mismatch, ternary(isnan(S(k).expect), "true", "expected blend"), 100*err, 100*S(k).tol);
        pass(k) = isscalar(m) && m == S(k).method && mis == S(k).mismatch && err <= S(k).tol;
        fprintf("   %s\n", passFail(pass(k)));
    end
    fprintf("\nOverall: %s\n", passFail(all(pass)));
end

function o = ternary(c, a, b), if c, o = a; else, o = b; end, end
function s = passFail(ok), if ok, s = "PASS"; else, s = "FAIL"; end, end
