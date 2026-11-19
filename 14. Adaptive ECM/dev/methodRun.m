function M = methodRun(method, profile, hours, seed)
% One accelerator run for the method / profile comparison; summary metrics.
if nargin < 4, seed = 1; end
ECM = ecmParams(Method=method, Profile=profile, Seed=seed, ErrShape="smooth");
assignin("base", "ECM", ECM);
set_param("ecmOffline", "FastRestart", "off", "SimulationMode", "accelerator", "StopTime", string(hours*3600));
L = ecmGetLog(sim("ecmOffline"));
[~, R] = evalc("ecmEvaluate(L, ECM)");
M.method = method; M.profile = profile; M.seed = seed; M.hours = hours;
h = L.t / 3600; late = h > hours - 24; dis = late & L.mode == 1;
nm = ["r0" "r1" "tau"]; ee = ["r0e" "r1e" "taue"]; rr = ["r0Rls" "r1Rls" "tauRls"];
for k = 1:3
    E = abs(L.(ee(k)) - L.(nm(k))) ./ L.(nm(k)) * 100;
    Er = abs(L.(rr(k)) - L.(nm(k))) ./ L.(nm(k)) * 100;
    M.(nm(k) + "_op_p50") = prctile(E(late, :), 50, "all");
    M.(nm(k) + "_op_p95") = prctile(E(late, :), 95, "all");
    M.(nm(k) + "_raw_p50") = prctile(Er(dis, :), 50, "all");
    M.(nm(k) + "_nodes_med") = R.nodes.(nm(k)).medAbs;
end
M.Q_final_max = max(abs(R.finalErr_pct(:, 4)));
M.nConv = sum(~isnan(R.conv.convT)); M.nLeft = sum(~isnan(R.conv.leftT));
M.convT_med_h = median(R.conv.convT / 3600, "omitnan");
end
