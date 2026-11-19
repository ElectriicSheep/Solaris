%% checkBmsSoc.m
% SOC accuracy of the BMS (SE layer, coulomb counting) over one pass of CYCLE A
% (1369 s, mean ~2.8 A pack, SOC falls ~4.5 %). Normal mode: Accelerator gave no
% speed-up (the detailed 91-cell Simscape plant dominates; measured 2026-11-19). ~12-15 min.
% Start: plant SOC 0.9, stored record correct (short rest -> stored SOC used), so the
% error shown is from counting and the modelled current-sensor error only.
% Pass: max |SOC_BMS - SOC_true| over all groups and the whole run <= 1 % (placeholder
% criterion).
% Limitation: plant and BMS use the same capacity and OCV data, so this checks the
% logic and sensor-error effect, not real-cell accuracy.

runCheck();

function runCheck()
    mdl = "bmsTestPlatform";  load_system(mdl);
    rtc = 1e6;  nG = 13;  soc0 = 0.9;  T = 1369 + 5;
    rec = struct("socGroup", soc0*ones(nG,1), "tSave", rtc - 600, "valid", true);
    in = Simulink.SimulationInput(mdl).setModelParameter("StopTime", string(T)) ...
        .setVariable("LOAD_profile", 3).setVariable("LOAD_scale", 1).setVariable("SOC0", soc0) ...
        .setVariable("HW_nvm", rec).setVariable("HW_rtcStart", rtc);
    tic;  [~, out] = evalc("sim(in)");  wall = toc;
    fprintf("\n=== one pass of CYCLE A (%d s simulated, Normal mode): %.0f s wall (%.2f wall s per sim s incl. build)\n", T, wall, wall/T);
    L = printBmsLog(out, true);
    fprintf("   log records: %d (%d INFO, %d MINOR, %d MAJOR, %d FAULT)\n", height(L), sum(L.severity == "INFO"), ...
        sum(L.severity == "MINOR"), sum(L.severity == "MAJOR"), sum(L.severity == "FAULT"));
    for j = find(L.severity ~= "INFO")', fprintf("   %8.2f s  %-5s %-14s %s\n", L.t(j), L.severity(j), L.faultCode(j), L.text(j)); end
    [tT, sT] = getLoggedSignal(out, "socTrue", "EVAL");  [tB, sB] = getLoggedSignal(out, "socBms", "EVAL");
    sTi = interp1(tT, sT, tB);  ok = tB > 3;                    % after start-up
    e = abs(sB(ok, :) - sTi(ok, :));  [eMax, iMax] = max(e(:));  [kMax, gMax] = ind2sub(size(e), iMax);
    tOk = tB(ok);
    fprintf("   true pack SOC %.2f %% -> %.2f %% | BMS pack SOC %.2f %% -> %.2f %%\n", 100*min(sTi(find(ok,1),:)), 100*min(sT(end,:)), ...
        100*min(sB(find(ok,1),:)), 100*min(sB(end,:)));
    fprintf("   max |SOC_BMS - true| = %.3f %% (group %d at %.0f s); at the end %.3f %% (limit 1.0 %%)\n", ...
        100*eMax, gMax, tOk(kMax), 100*max(abs(sB(end,:) - sT(end,:))));
    fprintf("\nOverall: %s\n", passFail(eMax <= 0.01));
end
function s = passFail(ok), if ok, s = "PASS"; else, s = "FAIL"; end, end
