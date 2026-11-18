function s = soaCheck(v, lim, iRest)
%SOACHECK BMS SOA layer: safe-operating-area limit checks, foxBMS style.
%   s = soaCheck(v, lim, iRest)
%   v      BMS_validData (validated values and their extremes)
%   lim    struct of limits, each [MOL RSL MSL]:
%            .vMax .vMin                  group voltage, V
%            .iDchg .iChg                 pack current magnitude, A (discharge / charge)
%            .tMaxDchg .tMinDchg          temperature window while discharging or at rest, K
%            .tMaxChg  .tMinChg           temperature window while charging, K
%   iRest  current below which the pack counts as not charging, A
%   s      BMS_soaData: for each quantity, [MOL RSL MSL] = limit exceeded
%
%   MOL (maximum operating limit) < RSL (recommended safety limit) < MSL (maximum
%   safety limit). No debouncing here: DIAG debounces. Current is discharge positive,
%   so charging is iPack < -iRest; the charge temperature window then applies.

    charging = v.iPack < -iRest;
    if charging
        tHi = lim.tMaxChg(:);   tLo = lim.tMinChg(:);
    else
        tHi = lim.tMaxDchg(:);  tLo = lim.tMinDchg(:);
    end

    % Fields in the order of BMS_soaData
    s.overVoltage     = v.vMax   > lim.vMax(:);
    s.underVoltage    = v.vMin   < lim.vMin(:);
    s.overCurrentDchg = v.iPack  > lim.iDchg(:);
    s.overCurrentChg  = -v.iPack > lim.iChg(:);
    s.overTemp        = v.tMax   > tHi;
    s.underTemp       = v.tMin   < tLo;
end
