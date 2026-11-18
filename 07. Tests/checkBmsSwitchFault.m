%% checkBmsSwitchFault.m
% Tests the BMS state machine against injected main-switch faults (PLANT_switchFault).
%
% Three runs of bmsTestPlatform, constant 1C load (LOAD_profile 1), sensor errors on:
%   0  no fault     : INITIALIZATION -> NORMAL, never ERROR; current flows
%   1  stuck open   : the switch never closes. Each close attempt times out after
%                     BMS_tCloseMax -> ERROR; retry after BMS_tRecover; after
%                     BMS_nRetryMax ERROR entries the BMS stays in ERROR. No current.
%                     ERROR cause SWITCH_STUCK_OPEN; latched at the end.
%   2  welded       : the switch never opens. Feedback reads closed while commanded
%                     open, so the start-up check never passes; INITIALIZATION times out
%                     after BMS_tInitMax -> ERROR; retries as above. The BMS never
%                     commands the switch closed, yet current flows: a welded switch
%                     cannot be opened by the BMS (the reason for a fuse and an
%                     independent protection layer). ERROR cause SWITCH_WELDED;
%                     latched at the end.
% Checks are on the sequence of states and the number of ERROR entries, not on exact
% transition times (those depend on the sample rates; they are printed for inspection).
%
% Before running: the BMS output line in SM_bms must be logged as bmsOutLog, and
% iPack in PLANT must be logged.

runCheck();

function runCheck()
    mdl = "bmsTestPlatform";
    load_system(mdl);
    dd   = Simulink.data.dictionary.open(fullfile(fileparts(which("bms.slx")), "bms.sldd"));
    sec  = getSection(dd, "Design Data");
    prm  = @(n) getValue(getEntry(sec, n)).Value;
    nRetry = prm("BMS_nRetryMax");
    % Long enough for nRetry failed attempts of the slower (welded) case, plus margin
    tStop = ceil(nRetry * (prm("BMS_tInitMax") + prm("BMS_tRecover")) + 10);

    fprintf("\n=== BMS switch-fault test: %g s per run, BMS_nRetryMax = %d\n", tStop, nRetry);
    names = ["no fault", "stuck open", "welded"];
    pass = true(1, 3);
    for f = 0:2
        in  = Simulink.SimulationInput(mdl) ...
            .setModelParameter("StopTime", num2str(tStop)) ...
            .setVariable("LOAD_profile", 1) ...
            .setVariable("PLANT_switchFault", f);
        out = sim(in);
        b   = out.logsout.get("bmsOutLog").Values;
        st  = b.state.Data(:);  tS = b.state.Time(:);
        cmd = b.contactorCmd.Data(:);
        cause = b.errorCause.Data(:);  lat = b.latched.Data(:);
        [~, i] = getLoggedSignal(out, "iPack", "PLANT");

        k = [1; find(diff(double(st)) ~= 0) + 1];          % state changes
        fprintf("\n-- fault %d (%s)\n", f, names(f+1));
        for j = k'
            fprintf("   t = %6.2f s  -> %-14s", tS(j), string(st(j)));
            if st(j) == BMS_state.ERROR, fprintf(" cause %s, latched %d", string(cause(j)), lat(j)); end
            fprintf("\n");
        end
        errCauses = unique(cause(st == BMS_state.ERROR));
        nErr    = nnz(st(k) == BMS_state.ERROR);
        reachedNormal = any(st == BMS_state.NORMAL);
        current = any(abs(i) > 0.01);
        fprintf("   ERROR entries %d, reached NORMAL %d, switch ever commanded closed %d, current flowed %d\n", ...
            nErr, reachedNormal, any(cmd), current);

        switch f
            case 0, ok = reachedNormal && nErr == 0 && current && st(end) == BMS_state.NORMAL && ~any(lat);
            case 1, ok = ~reachedNormal && nErr == nRetry && ~current && st(end) == BMS_state.ERROR ...
                         && isequal(errCauses, BMS_eventCode.SWITCH_STUCK_OPEN) && lat(end);
            case 2, ok = ~reachedNormal && nErr == nRetry && ~any(cmd) && current && st(end) == BMS_state.ERROR ...
                         && isequal(errCauses, BMS_eventCode.SWITCH_WELDED) && lat(end);
        end
        pass(f+1) = ok;
        fprintf("   %s\n", passFail(ok));
    end
    fprintf("\nOverall: %s\n", passFail(all(pass)));
end

function s = passFail(ok)
    if ok, s = "PASS"; else, s = "FAIL"; end
end
