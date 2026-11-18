function p = plausCheck(m, vRange, iMax, tRange, tStale, Ts, boot)
%PLAUSCHECK BMS PLAUS layer: per-channel plausibility of the measurements.
%   p = plausCheck(m, vRange, iMax, tRange, tStale, Ts, boot)
%   m       BMS_measData (calibrated measurements with sample timestamps)
%   vRange  [min max] plausible group voltage, V    (outside = sensor fault, not a cell fault)
%   iMax    largest plausible |pack current|, A
%   tRange  [min max] plausible temperature, K
%   tStale  [V I T C] longest time a timestamp may stay unchanged, s
%   Ts      BMS task period, s (this function is called once per task)
%   boot    restart as after a power-up (power on or reset): history cleared
%   p       BMS_plausData: the measurements plus one validity flag per channel, and
%           measReady (every sensor type has delivered a new sample since start-up)
%
%   A channel is valid when its value is in its plausible range AND its sample is
%   fresh. Freshness is judged by whether the sample's timestamp has advanced, not by
%   comparing it with the BMS clock, so the sensor and BMS clocks need not agree.
%   Start-up: values present before a sensor type's FIRST new sample (timestamp change)
%   are power-up contents, not measurements, so that type is invalid until its first
%   sample arrives. measReady latches true once all four types have delivered one; DIAG
%   does not evaluate faults before then (a sensor that never delivers is caught by the
%   state machine's INITIALIZATION time-out).
%   No debouncing here: DIAG debounces. Called from one MATLAB Function block only
%   (the timestamp history is kept in persistent variables).

    persistent tsLast age received
    ts = [m.tsV; m.tsI; m.tsT; m.tsC];
    if isempty(tsLast) || boot
        tsLast   = ts;
        age      = zeros(4, 1);
        received = false(4, 1);
    end
    fresh = ts ~= tsLast;
    age(fresh)  = 0;
    age(~fresh) = age(~fresh) + Ts;
    received(fresh) = true;
    tsLast = ts;
    ok = (age <= tStale(:)) & received;      % fresh enough AND a real sample has arrived

    % Fields in the order of BMS_plausData
    p.vGroup      = m.vGroup;
    p.iPack       = m.iPack;
    p.tSensor     = m.tSensor;
    p.vValid      = (m.vGroup  >= vRange(1)) & (m.vGroup  <= vRange(2)) & ok(1);
    p.iValid      = (abs(m.iPack) <= iMax) & ok(2);
    p.tValid      = (m.tSensor >= tRange(1)) & (m.tSensor <= tRange(2)) & ok(3);
    p.contactorFb = m.contactorFb;
    p.cValid      = ok(4);
    p.measReady   = all(received);
end
