%% checkBmsEventLog.m
% Tests the BMS event log (LOG layer) with injected measurement faults (SENS_FAULT,
% platform only). Each scenario must produce the listed records, in this order (other
% records may appear in between). No load current (LOAD_profile 0), so the group
% voltages sit near their open-circuit value; sensor errors on.
%
%   1 Over-voltage ramp on group 5 (+0.01 V/s from 5 s): MINOR -> MAJOR -> FAULT
%     OV-M3-G05, then ERROR with cause DIAG_FAULT
%   2 Brief over-voltage on group 3 (+0.08 V for 0.3 s at 6 s): one MAJOR excursion
%     OV-M2-G03 and no FAULT
%   3 Temperature readings stop updating at 5 s: after BMS_tStale(T) = 3 s the whole
%     type is stale -> FAULT ST-ALL, ERROR (DIAG_FAULT)
%   4 Voltage channel of group 7 open for 2 s from 5 s: FAULT SV-M4-G07, ERROR, then
%     the fault clears, retry (attempt 2) and back to NORMAL
% Prints each scenario's log (printBmsLog) and PASS/FAIL.

runCheck();

function runCheck()
    mdl = "bmsTestPlatform";  load_system(mdl);
    S = struct("name", {}, "vars", {}, "tStop", {}, "expect", {}, "forbid", {});
    S(end+1) = struct("name", "over-voltage ramp, group 5", ...
        "vars", {{"SENS_faultType", 1, "SENS_faultChannel", 5, "SENS_faultValue", 0.15, "SENS_faultStart", 5, "SENS_faultRamp", 15}}, ...
        "tStop", 15, "expect", ["MINOR OV-M3-G05", "MAJOR OV-M3-G05", "FAULT OV-M3-G05", "FAULT ERR-DIAG"], "forbid", strings(1,0));
    S(end+1) = struct("name", "brief over-voltage, group 3", ...
        "vars", {{"SENS_faultType", 1, "SENS_faultChannel", 3, "SENS_faultValue", 0.08, "SENS_faultStart", 6, "SENS_faultDuration", 0.3}}, ...
        "tStop", 10, "expect", "MAJOR OV-M2-G03", "forbid", ["FAULT OV-M2-G03", "FAULT ERR-DIAG"]);
    S(end+1) = struct("name", "temperature readings stop updating", ...
        "vars", {{"SENS_faultType", 3, "SENS_faultStart", 5}}, ...
        "tStop", 12, "expect", ["FAULT ST-ALL", "FAULT ERR-DIAG"], "forbid", strings(1,0));
    S(end+1) = struct("name", "voltage channel open, group 7, for 2 s", ...
        "vars", {{"SENS_faultType", 4, "SENS_faultChannel", 7, "SENS_faultStart", 5, "SENS_faultDuration", 2}}, ...
        "tStop", 18, "expect", ["FAULT SV-M4-G07", "FAULT ERR-DIAG", "INFO START", "INFO SWITCH"], "forbid", "FAULT RETRY_LIMIT");

    pass = true(1, numel(S));
    for k = 1:numel(S)
        in = Simulink.SimulationInput(mdl).setModelParameter("StopTime", num2str(S(k).tStop)) ...
            .setVariable("LOAD_profile", 0);
        v = S(k).vars;
        for j = 1:2:numel(v), in = in.setVariable(v{j}, v{j+1}); end
        out = sim(in);
        fprintf("\n=== %d. %s\n", k, S(k).name);
        T = printBmsLog(out);
        keys = T.severity + " " + T.faultCode;
        % expected records in order (as a subsequence)
        p = 0;  ok = true;
        for e = S(k).expect
            i = find(startsWith(keys(p+1:end), e) & T.active(p+1:end), 1);
            if isempty(i), ok = false; fprintf("   missing (in order): %s\n", e); else, p = p + i; end
        end
        for f = S(k).forbid
            if any(startsWith(keys, f) & T.active), ok = false; fprintf("   unexpected: %s\n", f); end
        end
        pass(k) = ok;
        fprintf("   %s\n", passFail(ok));
    end
    fprintf("\nOverall: %s\n", passFail(all(pass)));
end

function s = passFail(ok)
    if ok, s = "PASS"; else, s = "FAIL"; end
end
