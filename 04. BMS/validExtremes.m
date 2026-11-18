function v = validExtremes(p, lim)
%VALIDEXTREMES BMS BMSVL layer: validated values, pack extremes over VALID channels only.
%   v = validExtremes(p, lim)
%   p    BMS_plausData (measurements with per-channel validity, measReady)
%   lim  BMS_soaLim (only used for the value reported before any valid sample)
%   v    BMS_validData
%
%   vMin/vMax/tMin/tMax are taken over valid channels only, so an implausible channel
%   is reported once (as invalid, via allValid) and never also as an SOA limit
%   violation. If no channel of a type is valid, the last valid extreme is held.
%   Before the first valid sample the extremes are the middle of the MOL window (inside
%   every SOA limit); DIAG does not evaluate before measReady, so this value never
%   causes a fault. Called from one MATLAB Function block only (held values are
%   persistent).

    persistent vLo vHi tLo tHi iv iV it iT
    if isempty(vLo)
        iv = uint8(0);  iV = uint8(0);  it = uint8(0);  iT = uint8(0);
        vMid = (lim.vMin(1) + lim.vMax(1)) / 2;
        tMid = (lim.tMinDchg(1) + lim.tMaxDchg(1)) / 2;
        vLo = vMid;  vHi = vMid;  tLo = tMid;  tHi = tMid;
    end
    if any(p.vValid)
        x = p.vGroup;  x(~p.vValid) = realmax;   [vLo, k] = min(x);  iv = uint8(k);
        x = p.vGroup;  x(~p.vValid) = -realmax;  [vHi, k] = max(x);  iV = uint8(k);
    end
    if any(p.tValid)
        x = p.tSensor; x(~p.tValid) = realmax;   [tLo, k] = min(x);  it = uint8(k);
        x = p.tSensor; x(~p.tValid) = -realmax;  [tHi, k] = max(x);  iT = uint8(k);
    end

    % Fields in the order of BMS_validData
    v.vGroup      = p.vGroup;
    v.iPack       = p.iPack;
    v.tSensor     = p.tSensor;
    v.vMin        = vLo;
    v.vMax        = vHi;
    v.tMin        = tLo;
    v.tMax        = tHi;
    v.allValid    = all(p.vValid) && p.iValid && all(p.tValid) && p.cValid;
    v.contactorFb = p.contactorFb;
    v.measReady   = p.measReady;
    v.vMinIdx     = iv;      % WHERE the extremes are (for fault codes); held with the values
    v.vMaxIdx     = iV;
    v.tMinIdx     = it;
    v.tMaxIdx     = iT;
end
