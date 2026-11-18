%% checkBmsPower.m
% Tests the power and reset buttons (PWR layer, OFF/ON states of the state machine).
% Buttons are pressed on the platform (BMS_HW: HW_powerPress / HW_resetPress, rows
% [start duration] s). Constant 1C load, sensor errors on.
%
%   1 no press                 -> stays OFF, switch never closes, no current
%   2 power pressed 0.5 s      -> too short (< BMS_tPowerPress): stays OFF
%   3 on, off at 10 s, on at 20 s -> POWER_ON, NORMAL, POWER_OFF, OFF (no current), POWER_ON,
%                                SOC re-initialised from the record saved at switch-off
%                                (rest ~10 s, so mostly the stored value): the BMS SOC after
%                                the restart is within 0.2 % of its value before switch-off
%   4 switch stuck open, reset pressed at 20 s (acts at ~23 s) -> ERROR latched after 3 attempts; RESET clears it:
%                                start-up check attempt 1 again, SOC initialised from OCV
% Prints each scenario's log (printBmsLog) and PASS/FAIL.

runCheck();

function runCheck()
    mdl = "bmsTestPlatform";  load_system(mdl);
    none = [-1 0; -1 0; -1 0; -1 0];
    S = struct("name", {}, "vars", {}, "tStop", {}, "check", {});
    S(end+1) = struct("name", "no press", "vars", {{"HW_powerPress", none}}, "tStop", 5, "check", @c1);
    S(end+1) = struct("name", "power pressed 0.5 s (too short)", "vars", {{"HW_powerPress", [0 0.5; none(1:3,:)]}}, "tStop", 5, "check", @c1);
    S(end+1) = struct("name", "on, off at 10 s, on again at 20 s", ...
        "vars", {{"HW_powerPress", [0 1.2; 10 1.2; 20 1.2; -1 0]}}, "tStop", 26, "check", @c3);
    S(end+1) = struct("name", "switch stuck open, reset at 20 s", ...
        "vars", {{"PLANT_switchFault", 1, "HW_resetPress", [20 3.2; none(1:3,:)]}}, "tStop", 30, "check", @c4);

    pass = true(1, numel(S));
    for k = 1:numel(S)
        in = Simulink.SimulationInput(mdl).setModelParameter("StopTime", num2str(S(k).tStop)).setVariable("LOAD_profile", 1);
        v = S(k).vars;  for j = 1:2:numel(v), in = in.setVariable(v{j}, v{j+1}); end
        [~, out] = evalc("sim(in)");
        fprintf("\n=== %d. %s\n", k, S(k).name);
        T = printBmsLog(out);
        [ok, msg] = S(k).check(out, T);
        fprintf("   %s  %s\n", passFail(ok), msg);
        pass(k) = ok;
    end
    fprintf("\nOverall: %s\n", passFail(all(pass)));
end

function [ok, msg] = c1(out, T)
    b = out.logsout.get("bmsOutLog").Values;  [~, i] = getLoggedSignal(out, "iPack", "PLANT");
    ok = all(b.state.Data(:) == BMS_state.OFF) && ~any(b.contactorCmd.Data(:)) && ~any(abs(i) > 0.01) && ~any(T.faultCode == "PWR");
    msg = sprintf("(always OFF %d, switch never commanded %d, no current %d)", all(b.state.Data(:) == BMS_state.OFF), ~any(b.contactorCmd.Data(:)), ~any(abs(i) > 0.01));
end

function [ok, msg] = c3(out, T)
    keys = T.severity + " " + T.faultCode + " " + string(T.text);
    seq = ["power button: BMS switched on", "state -> NORMAL", "power button: main switch opened", "state -> OFF", ...
           "power button: BMS switched on", "SOC initialised", "state -> NORMAL"];
    p = 0;  ok = true;
    for e = seq
        i = find(contains(keys(p+1:end), e), 1);
        if isempty(i), ok = false; msg = "missing: " + e; return, end
        p = p + i;
    end
    [t, s] = getLoggedSignal(out, "socBms", "EVAL");  b = out.logsout.get("bmsOutLog").Values;
    st = b.state.Data(:);  ts = b.state.Time(:);
    tOff = ts(find(st == BMS_state.OFF & ts > 5, 1));  tOn = ts(find(st == BMS_state.NORMAL & ts > tOff, 1));
    before = interp1(t, s(:,1), tOff - 0.2);  after = interp1(t, s(:,1), tOn);
    [~, i] = getLoggedSignal(out, "iPack", "PLANT");  [ti, ~] = getLoggedSignal(out, "iPack", "PLANT");
    offCurrent = max(abs(i(ti > tOff + 0.3 & ti < tOn - 0.5)));
    [tT, sT] = getLoggedSignal(out, "socTrue", "EVAL");  trueBefore = interp1(tT, sT(:,1), tOff - 0.2);
    ok = abs(after - before) < 0.002 && abs(before - trueBefore) < 0.01 && offCurrent < 0.01;
    msg = sprintf("(group-1 SOC before off %.4f (true %.4f), after restart %.4f; max current while off %.3f A)", before, trueBefore, after, offCurrent);
end

function [ok, msg] = c4(out, T)
    keys = T.severity + " " + T.faultCode + " " + string(T.text);
    seq = ["ERR-LATCHED", "reset button", "start-up check begun (attempt 1)", "SOC initialised from OCV"];
    p = 0;  ok = true;  msg = "";
    for e = seq
        i = find(contains(keys(p+1:end), e), 1);
        if isempty(i), ok = false; msg = "missing (in order): " + e; return, end
        p = p + i;
    end
    b = out.logsout.get("bmsOutLog").Values;  lat = b.latched.Data(:);  tl = b.latched.Time(:);
    ok = any(lat(tl < 20)) && ~lat(find(tl > 23.5, 1));
    msg = sprintf("(latched before reset %d, cleared after reset %d)", any(lat(tl < 20)), ~lat(find(tl > 23.5, 1)));
end

function s = passFail(ok), if ok, s = "PASS"; else, s = "FAIL"; end, end
