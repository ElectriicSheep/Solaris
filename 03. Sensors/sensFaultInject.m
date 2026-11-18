function m = sensFaultInject(m, faultType, ch, mag, tStart, tDur, tRamp)
%SENSFAULTINJECT Platform-side fault injection on the measurements sent to the BMS.
%   m = sensFaultInject(m, faultType, ch, mag, tStart, tDur, tRamp)
%   m          SENS_measBus at the BMS rate (after the Rate Transition)
%   faultType  0 none
%              1 voltage offset:   vGroup(ch) + mag V (ramped in over tRamp)
%              2 temperature offset: tSensor(ch) + mag K (ramped in over tRamp)
%              3 temperature readings stop updating: all tSensor and tsT frozen
%                (e.g. lost link to the temperature board; per-type staleness)
%              4 voltage channel open: vGroup(ch) reads 0 V
%   ch         channel: group 1-13 (types 1, 4) or sensor 1-26 (type 2)
%   mag        offset magnitude, V or K (types 1, 2)
%   tStart     fault starts at this time, s;  tDur  lasts this long, s;
%   tRamp      offsets rise linearly from 0 to mag over this time, s (0 = step)
%   "Now" is the voltage sample's timestamp (tsV). Platform only: never part of the BMS.
%   Called from one MATLAB Function block only (frozen values are persistent).

    persistent frozenT frozenTs
    if isempty(frozenT)
        frozenT = m.tSensor;  frozenTs = m.tsT;
    end
    t = m.tsV;
    on = faultType ~= 0 && t >= tStart && t < tStart + tDur;
    if tRamp > 0
        k = min(1, max(0, (t - tStart) / tRamp));
    else
        k = 1;
    end
    if ~on || faultType ~= 3
        frozenT = m.tSensor;  frozenTs = m.tsT;
    end
    if on
        switch faultType
            case 1, if ch >= 1 && ch <= numel(m.vGroup),  m.vGroup(ch)  = m.vGroup(ch)  + k*mag; end
            case 2, if ch >= 1 && ch <= numel(m.tSensor), m.tSensor(ch) = m.tSensor(ch) + k*mag; end
            case 3, m.tSensor = frozenT;  m.tsT = frozenTs;
            case 4, if ch >= 1 && ch <= numel(m.vGroup),  m.vGroup(ch)  = 0; end
        end
    end
end
