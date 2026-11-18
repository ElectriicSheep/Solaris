%% checkBmsSocRecal.m
% Tests the runtime SOC recalibration at rest (SE layer, restRecal blocks; as foxBMS):
% while |iPack| < BMS_iRest for BMS_tRestRecal, SOC is set from OCV.
% BMS_tRestRecal is shortened to 20 s for the test (restored afterwards).
%
%   1 no load, stored record 5 % too high after a short rest (kept at start-up)
%     -> SOC stays at the stored value until ~20 s of rest, then one INFO SOC-RECAL
%        and SOC = OCV, within 1 % of the true SOC at the end
%   2 constant load (LOAD_profile 1) -> no SOC-RECAL (pack never at rest once the switch closes)
% Limitation: the plant has no voltage relaxation, so OCV is exact as soon as the
% current stops; real cells need BMS_tRestRecal to relax (placeholder value).

runCheck();

function runCheck()
    mdl = "bmsTestPlatform";  load_system(mdl);
    dd = Simulink.data.dictionary.open("bms.sldd");  e = getEntry(getSection(dd, "Design Data"), "BMS_tRestRecal");
    p = getValue(e);  orig = p.Value;  tTest = 20;
    restore = onCleanup(@() setTest(dd, e, orig));
    setTest(dd, e, tTest);
    rtc = 1e6;  nG = 13;
    rec = struct("socGroup", 0.65*ones(nG,1), "tSave", rtc - 600, "valid", true);
    S = struct("name", {"no load, stored SOC 5 % high", "constant load"}, "load", {0, 1}, "expectRecal", {true, false});
    pass = true(1, numel(S));
    for k = 1:numel(S)
        in = Simulink.SimulationInput(mdl).setModelParameter("StopTime", "40") ...
            .setVariable("LOAD_profile", S(k).load).setVariable("SOC0", 0.6) ...
            .setVariable("HW_nvm", rec).setVariable("HW_rtcStart", rtc);
        [~, out] = evalc("sim(in)");
        fprintf("\n=== %d. %s (BMS_tRestRecal = %d s for the test)\n", k, S(k).name, tTest);
        T = printBmsLog(out, true);
        j = find(T.faultCode == "SOC-RECAL" | T.faultCode == "SOC");
        for i = j', fprintf("   %6.2f s  %-5s %-10s %s\n", T.t(i), T.severity(i), T.faultCode(i), T.text(i)); end
        nRecal = sum(T.faultCode == "SOC-RECAL");
        [tS, sT] = getLoggedSignal(out, "socTrue", "EVAL");  [tB, sB] = getLoggedSignal(out, "socBms", "EVAL");
        if S(k).expectRecal
            tR = T.t(find(T.faultCode == "SOC-RECAL", 1));  if isempty(tR), tR = NaN; end
            before = max(abs(sB(find(tB <= 15, 1, "last"), :) - 0.65));
            errEnd = max(abs(sB(end, :) - sT(end, :)));
            fprintf("   recal events %d (expected 1) at %.1f s | before: max |SOC_BMS - stored| = %.2f %% | end: max |SOC_BMS - true| = %.2f %% (limit 1.0 %%)\n", ...
                nRecal, tR, 100*before, 100*errEnd);
            pass(k) = nRecal == 1 && tR > tTest && before < 0.005 && errEnd <= 0.01;
        else
            fprintf("   recal events %d (expected 0) | pack SOC fell %.2f %% (true %.2f %%)\n", nRecal, ...
                100*(min(sB(1+find(tB > 3, 1), :)) - min(sB(end, :))), 100*(min(sT(1+find(tS > 3, 1), :)) - min(sT(end, :))));
            pass(k) = nRecal == 0;
        end
        fprintf("   %s\n", passFail(pass(k)));
    end
    fprintf("\nOverall: %s\n", passFail(all(pass)));
end

function setTest(dd, e, v)
    p = getValue(e);  p.Value = v;  setValue(e, p);  saveChanges(dd);
end
function s = passFail(ok), if ok, s = "PASS"; else, s = "FAIL"; end, end
