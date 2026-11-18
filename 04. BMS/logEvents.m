function [events, count, dropped] = logEvents(v, d, p, state, cmd, cause, latched, lim, iRest, Ts)
%LOGEVENTS BMS LOG layer: turns changes in the BMS into time-stamped log records.
%   [events, count, dropped] = logEvents(v, d, p, state, cmd, cause, latched, lim, iRest, Ts)
%   v        BMS_validData  (extremes, their group/sensor index, iPack, measReady)
%   d        DIAG_bus       (level per quantity, excursion pulses, sensorInvalid)
%   p        BMS_plausData  (per-channel validity: which sensor is invalid)
%   state    BMS_state      cmd     main switch command (true = close)
%   cause    BMS_eventCode  why the BMS is in ERROR     latched  ERROR latched
%   lim      BMS_soaLim     (limit values written into limit records)
%   iRest    BMS_iRest      (charging = iPack < -iRest selects the charge temperature limits)
%   Ts       BMS task period, s (this function is called once per task)
%   events   BMS_event array (one per slot): this step's records, most severe first;
%            unused slots have severity NONE
%   count    records produced since start-up;  dropped  records lost (slots full)
%
%   Records (severity, code):
%     INFO  MEAS_READY          every sensor type has delivered its first sample
%     INFO  STATE_CHANGE        every state change (location = new state, value = previous)
%     INFO  START_CHECK_BEGIN   INITIALIZATION entered (location = attempt number)
%     INFO  START_CHECK_PASSED  switch commanded closed in INITIALIZATION
%     INFO  SWITCH_CLOSED       NORMAL entered (feedback confirmed)
%     MINOR/MAJOR/FAULT <limit> debounced level of a quantity rose (MOL/RSL/MSL); a
%                               record with active = false when it falls back
%     MAJOR <limit>             MSL excursion: exceeded but too short to be a fault
%     FAULT SENSOR_x_INVALID    DIAG sensorInvalid set, per sensor type with an invalid
%                               channel (location = channel, 0 = several); cleared later
%     FAULT <ERROR cause>       ERROR entered; FAULT RETRY_LIMIT if latched;
%                               cause cleared (FAULT, active = false) when ERROR is left
%   A "cleared" record keeps the severity of what cleared, with active = false.
%   Limit records: location = worst group (voltage) or sensor (temperature), value =
%   that extreme (or the current), limit = the limit at that level.
%   Within one step, limit and sensor records come before the state-machine records, so
%   a specific fault is listed before the ERROR it caused.
%   Called from one MATLAB Function block only (history kept in persistent variables).

    nSlots = 6;                                   % = BMS_event slots on BMS_outBus
    persistent k prevState prevCmd prevCause prevLevel prevReady prevInv prevInvLoc count_ dropped_ attempt ...
               tracking peakVal peakLoc
    if isempty(k)
        prevInvLoc = zeros(4, 1, "uint8");
        tracking = false(6, 1);  peakVal = zeros(6, 1);  peakLoc = zeros(6, 1, "uint8");
        k = 0;  prevState = state;  prevCmd = false;  prevCause = BMS_eventCode.NONE;
        prevLevel = zeros(6, 1, "uint8");  prevReady = false;  prevInv = false(4, 1);
        count_ = uint32(0);  dropped_ = uint32(0);  attempt = uint8(0);
    end
    t = k * Ts;  k = k + 1;

    blank = struct("t", 0, "severity", BMS_severity.NONE, "code", BMS_eventCode.NONE, ...
        "active", false, "location", uint8(0), "level", uint8(0), "value", 0, "limit", 0, ...
        "state", state);
    c = repmat(blank, 24, 1);  n = 0;             % candidates for this step

    % --- limits: debounced level changes and MSL excursions ---
    charging = v.iPack < -iRest;
    for q = 1:6
        [code, loc, val, L3] = quantity(q, v, lim, charging);
        Ln = d.level(q);  Lp = prevLevel(q);
        if Ln > Lp
            n = n + 1; c(n) = rec(blank, t, sevOf(Ln), code, true, loc, Ln, val, L3(Ln));
        elseif Ln < Lp
            n = n + 1; c(n) = rec(blank, t, sevOf(Lp), code, false, loc, Lp, val, L3(Lp));
        end
        % track the worst reading while the MSL is exceeded (an excursion is only known
        % when it has ended, so its record carries the peak and where it occurred)
        if q == 2 || q == 6, beyond = val < L3(3); worse = val < peakVal(q);
        else,               beyond = val > L3(3); worse = val > peakVal(q); end
        if beyond && (~tracking(q) || worse)
            peakVal(q) = val;  peakLoc(q) = loc;
        end
        if d.excursion(q)
            n = n + 1; c(n) = rec(blank, t, BMS_severity.MAJOR, code, true, peakLoc(q), uint8(3), peakVal(q), L3(3));
        end
        tracking(q) = beyond;
    end

    % --- sensor validity (when DIAG's debounced sensorInvalid changes) ---
    sCodes = [BMS_eventCode.SENSOR_V_INVALID, BMS_eventCode.SENSOR_I_INVALID, ...
              BMS_eventCode.SENSOR_T_INVALID, BMS_eventCode.SENSOR_C_INVALID];
    nBad = [nnz(~p.vValid), nnz(~p.iValid), nnz(~p.tValid), nnz(~p.cValid)];
    first = [firstFalse(p.vValid), uint8(0), firstFalse(p.tValid), uint8(0)];
    inv = d.sensorInvalid & (nBad(:) > 0);
    for s = 1:4
        if inv(s) && ~prevInv(s)
            loc = first(s); if nBad(s) > 1, loc = uint8(0); end
            prevInvLoc(s) = loc;
            n = n + 1; c(n) = rec(blank, t, BMS_severity.FAULT, sCodes(s), true, loc, uint8(0), double(nBad(s)), 0);
        elseif ~d.sensorInvalid && prevInv(s)
            n = n + 1; c(n) = rec(blank, t, BMS_severity.FAULT, sCodes(s), false, prevInvLoc(s), uint8(0), 0, 0);
            inv(s) = false;
        elseif prevInv(s)
            inv(s) = true;                       % still reported as active
        end
    end

    % --- start-up and state machine (INFO, and FAULT for ERROR causes) ---
    if k == 1 || state ~= prevState
        if k == 1, prevVal = -1; else, prevVal = double(prevState); end
        n = n + 1; c(n) = rec(blank, t, BMS_severity.INFO, BMS_eventCode.STATE_CHANGE, true, uint8(state), 0, prevVal, 0);
        if state == BMS_state.INITIALIZATION
            attempt = attempt + 1;
            n = n + 1; c(n) = rec(blank, t, BMS_severity.INFO, BMS_eventCode.START_CHECK_BEGIN, true, attempt, 0, 0, 0);
        elseif state == BMS_state.NORMAL
            n = n + 1; c(n) = rec(blank, t, BMS_severity.INFO, BMS_eventCode.SWITCH_CLOSED, true, uint8(0), 0, 0, 0);
        elseif state == BMS_state.ERROR
            n = n + 1; c(n) = rec(blank, t, BMS_severity.FAULT, cause, true, uint8(0), 0, 0, 0);
            if latched
                n = n + 1; c(n) = rec(blank, t, BMS_severity.FAULT, BMS_eventCode.RETRY_LIMIT, true, attempt, 0, 0, 0);
            end
        end
        if k > 1 && prevState == BMS_state.ERROR && prevCause ~= BMS_eventCode.NONE
            n = n + 1; c(n) = rec(blank, t, BMS_severity.FAULT, prevCause, false, uint8(0), 0, 0, 0);
        end
    end
    if state == BMS_state.INITIALIZATION && cmd && ~prevCmd
        n = n + 1; c(n) = rec(blank, t, BMS_severity.INFO, BMS_eventCode.START_CHECK_PASSED, true, attempt, 0, 0, 0);
    end
    if v.measReady && ~prevReady
        n = n + 1; c(n) = rec(blank, t, BMS_severity.INFO, BMS_eventCode.MEAS_READY, true, uint8(0), 0, 0, 0);
    end

    % --- most severe first into the slots ---
    events = repmat(blank, nSlots, 1);  m = 0;
    for sv = [BMS_severity.FAULT, BMS_severity.MAJOR, BMS_severity.MINOR, BMS_severity.INFO]
        for j = 1:n
            if c(j).severity == sv && m < nSlots
                m = m + 1;  events(m) = c(j);
            end
        end
    end
    count_   = count_ + uint32(m);
    dropped_ = dropped_ + uint32(n - m);
    count = count_;  dropped = dropped_;

    prevState = state;  prevCmd = cmd;  prevCause = cause;  prevLevel = d.level;
    prevReady = v.measReady;  prevInv = inv;
end

function r = rec(r, t, sev, code, active, loc, lvl, val, limit)
    r.t = t;  r.severity = sev;  r.code = code;  r.active = active;
    r.location = uint8(loc);  r.level = uint8(lvl);  r.value = double(val);  r.limit = double(limit);
end

function s = sevOf(L)
    if L >= 3, s = BMS_severity.FAULT; elseif L == 2, s = BMS_severity.MAJOR; else, s = BMS_severity.MINOR; end
end

function i = firstFalse(x)
    i = uint8(0);
    for j = 1:numel(x)
        if ~x(j), i = uint8(j); return; end
    end
end

function [code, loc, val, L3] = quantity(q, v, lim, charging)
    % Event code, location, measured value and the three limits [MOL RSL MSL] of quantity q
    switch q
        case 1, code = BMS_eventCode.OVER_VOLTAGE;      loc = v.vMaxIdx;  val = v.vMax;   L3 = lim.vMax;
        case 2, code = BMS_eventCode.UNDER_VOLTAGE;     loc = v.vMinIdx;  val = v.vMin;   L3 = lim.vMin;
        case 3, code = BMS_eventCode.OVER_CURRENT_DCHG; loc = uint8(0);   val = v.iPack;  L3 = lim.iDchg;
        case 4, code = BMS_eventCode.OVER_CURRENT_CHG;  loc = uint8(0);   val = -v.iPack; L3 = lim.iChg;
        case 5
            code = BMS_eventCode.OVER_TEMP;  loc = v.tMaxIdx;  val = v.tMax;
            if charging, L3 = lim.tMaxChg; else, L3 = lim.tMaxDchg; end
        otherwise
            code = BMS_eventCode.UNDER_TEMP; loc = v.tMinIdx;  val = v.tMin;
            if charging, L3 = lim.tMinChg; else, L3 = lim.tMinDchg; end
    end
end
