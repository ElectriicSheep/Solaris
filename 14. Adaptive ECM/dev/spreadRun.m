function M = spreadRun(shape, spread, hours, seed)
% One ecmOffline run (accelerator) for the spreading test; returns summary metrics.
if nargin < 4, seed = 1; end
ECM = ecmParams(ErrShape=shape, Spread=spread, Seed=seed);
assignin("base", "ECM", ECM);
set_param("ecmOffline", "SimulationMode", "accelerator", "StopTime", string(hours*3600));
L = ecmGetLog(sim("ecmOffline"));
[~, R] = evalc("ecmEvaluate(L, ECM)");
M.shape = shape; M.spread = spread; M.seed = seed; M.hours = hours;
h = L.t / 3600;
first = h > 0.17 & L.mode ~= 3 & h < 7.5;                    % first discharge
late = h > hours - 24;
nm = ["r0" "r1" "tau"]; ee = ["r0e" "r1e" "taue"]; tb = ["tabR0" "tabR1" "tabTau"];
Tm = median(L.T(:));
for k = 1:3
    E = abs(L.(ee(k)) - L.(nm(k))) ./ L.(nm(k)) * 100;
    M.(nm(k) + "_first_p95") = prctile(E(first, :), 95, "all");
    M.(nm(k) + "_late_p95")  = prctile(E(late, :), 95, "all");
    % table at the operating temperature, all SOC points incl. never-visited 0 and 100 %
    X = L.(tb(k)); Tr = ecmTruthNow(ECM, L.sohr(end, :), nm(k)); e = zeros(11, 13);
    for g = 1:13
        est = interp1(ECM.est.tBpC, X(:, :, g)', Tm)';
        tru = interp1(ECM.est.tBpC, Tr(:, :, g)', Tm)';
        e(:, g) = 100 * (est - tru) ./ tru;
    end
    M.(nm(k) + "_tab_med") = median(abs(e), "all");
    M.(nm(k) + "_tab_p90") = prctile(abs(e(:)), 90);
    M.(nm(k) + "_tab_end") = median(abs(e([1 11], :)), "all");      % SOC 0 and 100 % (not visited)
    % whole table (all temperature columns), vs start
    S0 = abs(ECM.est.initErrTable.(nm(k))) * 100;
    M.(nm(k) + "_all_med") = median(abs(X - Tr) ./ Tr * 100, "all");
    M.(nm(k) + "_all_start") = median(S0, "all");
end
M.nConv = sum(~isnan(R.conv.convT));
M.nLeft = sum(~isnan(R.conv.leftT));
M.convT_med_h = median(R.conv.convT / 3600, "omitnan");
end
