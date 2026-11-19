%% checkAfe.m
% BQ76952 emulator (SM_bms/AFE) in the platform with the Simscape plant, no Pi (PI_link = 0):
% the pack protects itself. Faults are injected on what the chip sees (AFE_vOffset /
% AFE_tOffset), the load by LOAD_iConst. Each run 4 s, CONST load.
%   1 nominal 23.45 A        -> both FETs on, plant conducts 23.45 A, no fault
%   2 COV  (+0.6 V group 5)  -> CHG off after ~0.25 s (COV delay 244 ms), DSG on, discharge continues
%   3 OCD1 (60 A load)       -> DSG off after ~0.43 s (OCD1 delay 426 ms), current stops
%   4 OTC  (+40 K therm. 1)  -> CHG off after ~2 s (OTC 45 degC, delay 2 s), discharge continues
%   5 CUV  (-1.5 V group 3)  -> DSG off after ~0.25 s, current stops
% Delay measured as the chip defines it: from the Safety Alert bit (condition present) to the
% Safety Status bit and FET off; the chip model steps at 10 ms.

runCheck();

function runCheck()
    mdl = "bmsTestPlatform";  load_system(mdl);
    z13 = zeros(13, 1);  z7 = zeros(7, 1);
    S = struct("name", {}, "vOff", {}, "tOff", {}, "iLoad", {}, "fet", {}, "tTrip", {}, "conducts", {}, "bitA", {}, "bitB", {});
    S(end+1) = struct("name", "nominal 23.45 A", "vOff", z13, "tOff", z7, "iLoad", 23.45, "fet", "", "tTrip", NaN, "conducts", true, "bitA", 0, "bitB", 0);
    v = z13; v(5) = 0.6;
    S(end+1) = struct("name", "COV (+0.6 V on group 5)", "vOff", v, "tOff", z7, "iLoad", 23.45, "fet", "chg", "tTrip", 0.244, "conducts", true, "bitA", 8, "bitB", 0);
    S(end+1) = struct("name", "OCD1 (60 A load)", "vOff", z13, "tOff", z7, "iLoad", 60, "fet", "dsg", "tTrip", 0.426, "conducts", false, "bitA", 32, "bitB", 0);
    t = z7; t(1) = 40;
    S(end+1) = struct("name", "OTC (+40 K on thermistor 1)", "vOff", z13, "tOff", t, "iLoad", 23.45, "fet", "chg", "tTrip", 2.0, "conducts", true, "bitA", 0, "bitB", 16);
    v = z13; v(3) = -1.5;
    S(end+1) = struct("name", "CUV (-1.5 V on group 3)", "vOff", v, "tOff", z7, "iLoad", 23.45, "fet", "dsg", "tTrip", 0.244, "conducts", false, "bitA", 4, "bitB", 0);
    pass = false(1, numel(S));
    for k = 1:numel(S)
        in = Simulink.SimulationInput(mdl).setModelParameter("StopTime", "4") ...
            .setVariable("LOAD_profile", 1).setVariable("LOAD_iConst", S(k).iLoad) ...
            .setVariable("AFE_vOffset", S(k).vOff).setVariable("AFE_tOffset", S(k).tOff);
        [~, out] = evalc("sim(in)");
        a = out.logsout.get("afe").Values;  tr = out.logsout.get("truth").Values;
        t = a.chg.Time;  chg = a.chg.Data(:);  dsg = a.dsg.Data(:);  ssA = double(a.safetyA.Data(:));  ssB = double(a.safetyB.Data(:));
        iEnd = tr.iPack.Data(end);
        fprintf("\n=== %d. %s\n", k, S(k).name);
        if S(k).fet == ""
            ok = all(chg(t > 0.05)) && all(dsg(t > 0.05)) && abs(iEnd - S(k).iLoad) < 0.5 && all(ssA == 0) && all(ssB == 0);
            fprintf("   FETs on throughout %d, safety faults none %d, plant current at end %.2f A\n", all(chg(t > 0.05) & dsg(t > 0.05)), all(ssA == 0 & ssB == 0), iEnd);
        else
            f = a.(S(k).fet).Data(:);  other = a.(setdiff(["chg" "dsg"], S(k).fet)).Data(:);
            alA = double(a.alertA.Data(:));  alB = double(a.alertB.Data(:));
            kAl = find(bitand(alA, S(k).bitA) | bitand(alB, S(k).bitB), 1);   % condition first present
            kOff = find(t > 0.05 & ~f, 1);
            if isempty(kAl) || isempty(kOff), tOff = NaN; else, tOff = t(kOff) - t(kAl); end
            bitsOk = any(bitand(ssA, S(k).bitA)) || S(k).bitA == 0;  bitsOk = bitsOk && (any(bitand(ssB, S(k).bitB)) || S(k).bitB == 0);
            conducts = abs(iEnd) > 0.5;
            ok = abs(tOff - S(k).tTrip) <= 0.03 && bitsOk && all(other(t > 0.05)) == true && conducts == S(k).conducts;
            fprintf("   %s off %.2f s after the alert (delay %.3f s +- 0.03), other FET on %d, status bit set %d, plant current at end %.2f A (conducts %d, expected %d)\n", ...
                upper(S(k).fet), tOff, S(k).tTrip, all(other(t > 0.05)), bitsOk, iEnd, conducts, S(k).conducts);
        end
        pass(k) = ok;  fprintf("   %s\n", passFail(ok));
    end
    fprintf("\nOverall: %s\n", passFail(all(pass)));
end
function s = passFail(ok), if ok, s = "PASS"; else, s = "FAIL"; end, end
