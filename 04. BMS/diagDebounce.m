function d = diagDebounce(s, allValid, measReady, tSet, tClear, Ts, awake, boot)
%DIAGDEBOUNCE BMS DIAG layer: debounced fault flags and limit levels from SOA and PLAUS.
%   d = diagDebounce(s, allValid, measReady, tSet, tClear, Ts, awake, boot)
%   s         BMS_soaData (limit violations, each [MOL RSL MSL])
%   allValid  every measurement channel plausible (from BMSVL)
%   measReady every sensor type has delivered its first sample since start-up; until
%             then nothing is evaluated (no faults, counters held at zero)
%   tSet      a violation must persist this long to set, s
%   tClear    a set condition clears after being absent this long, s
%   Ts        BMS task period, s (this function is called once per task)
%   awake     BMS on; while off nothing is evaluated
%   boot      restart as after a power-up: counters cleared
%   d         DIAG_bus
%
%   Every limit level of every quantity is debounced the same way (18 conditions:
%   [OV UV OCdchg OCchg OT UT] x [MOL RSL MSL]), plus "a measurement is implausible".
%   level(q) = highest debounced level of quantity q: 0 none, 1 MOL, 2 RSL, 3 MSL.
%   Only MSL and implausible measurements are FATAL (anyFatal); MOL and RSL are reported
%   (level) for logging and, later, current derating. excursion(q) pulses for one step
%   when an MSL violation ends before it lasted tSet (too short to be a fault).
%   Debounced, not latched: latching and retries belong to the BMS state machine.
%   Called from one MATLAB Function block only (counters kept in persistent variables).

    nSet   = max(1, round(tSet   / Ts));
    nClear = max(1, round(tClear / Ts));
    R = [s.overVoltage(:)'; s.underVoltage(:)'; s.overCurrentDchg(:)'; ...
         s.overCurrentChg(:)'; s.overTemp(:)'; s.underTemp(:)'];       % 6 x 3 raw
    R = [R(:); ~allValid];                                              % 19 x 1

    persistent nOn nOff active
    ready = measReady && awake;
    if isempty(active) || ~ready || boot
        nOn = zeros(19, 1);  nOff = zeros(19, 1);  active = false(19, 1);
    end
    if ~ready
        R(:) = false;                        % power-up: no evaluation yet
    end

    % MSL violation that ends before it was debounced in = excursion
    endedEarly = ~R & (nOn > 0) & ~active;
    nOn(R)   = nOn(R) + 1;    nOff(R)  = 0;
    nOff(~R) = nOff(~R) + 1;  nOn(~R)  = 0;
    active(~active & nOn  >= nSet)   = true;
    active( active & nOff >= nClear) = false;

    A   = reshape(active(1:18), 6, 3);       % 6 quantities x [MOL RSL MSL]
    exc = reshape(endedEarly(1:18), 6, 3);
    lvl = zeros(6, 1, "uint8");
    for q = 1:6
        for L = 1:3
            if A(q, L), lvl(q) = uint8(L); end
        end
    end

    % Fields in the order of DIAG_bus
    d.overVoltage   = A(1, 3);
    d.underVoltage  = A(2, 3);
    d.overCurrent   = A(3, 3) || A(4, 3);
    d.overTemp      = A(5, 3);
    d.underTemp     = A(6, 3);
    d.sensorInvalid = active(19);
    d.anyFatal      = any(A(:, 3)) || active(19);
    d.level         = lvl;
    d.excursion     = exc(:, 3);
end
