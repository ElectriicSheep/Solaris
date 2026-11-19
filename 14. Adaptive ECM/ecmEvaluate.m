function R = ecmEvaluate(L, P, minCount)
%ECMEVALUATE Convergence summary of one run (log from ecmGetLog, parameters from ecmParams).
%   R = ecmEvaluate(L, P)
% Prints, per group, the time and energy to convergence of R0, R1, tau1 and capacity
% (ecmConvergence: +/-1 % held 10 min) and the error of the table nodes that were
% updated (weighted count >= minCount, default 100) against the true node values.
if nargin < 3, minCount = 100; end
E = cat(3, (L.r0e - L.r0) ./ L.r0, (L.r1e - L.r1) ./ L.r1, (L.taue - L.tau) ./ L.tau, ...
    (L.Qe - L.Q) ./ L.Q);
c = ecmConvergence(0.01, 600);
c.add(L.t, E, L.Wh);
R.conv = c;
R.table = c.table();
R.finalErr_pct = squeeze(100 * E(end, :, :));          % 13 x 4
md = @(D) reshape(median(D, [1 2]), 1, []);   % median over the table, per group
R.initErr_pct = 100 * [md(P.est.initErrTable.r0); md(P.est.initErrTable.r1); md(P.est.initErrTable.tau); P.est.initErr.Q]';
nm = ["r0" "r1" "tau"]; tb = ["tabR0" "tabR1" "tabTau"]; cn = ["cntR0" "cntR1" "cntTau"];
for k = 1:3
    Tn = ecmTruthNow(P, L.sohr(end, :), nm(k));
    e = 100 * (L.(tb(k)) - Tn) ./ Tn;
    v = L.(cn(k)) >= minCount;
    R.nodes.(nm(k)) = struct("n", nnz(v), "medAbs", median(abs(e(v))), "p90Abs", prctile(abs(e(v)), 90), ...
        "maxAbs", max(abs(e(v))), "within1pct", mean(abs(e(v)) <= 1));
end
fprintf("Run: %.1f h simulated. Converged = within +/-1 %% for 10 min (time, Wh at the start of that window)\n", L.t(end)/3600);
fprintf("Grp | R0: h  Wh   | R1: h  Wh   | tau1: h Wh  | Q: h  Wh    | final error %% (R0 R1 tau1 Q) | initial error %%\n");
for g = 1:13
    s = sprintf("%3d |", g);
    for p = 1:4
        if isnan(c.convT(g, p)), s = s + sprintf("   --       |");
        else, s = s + sprintf(" %5.2f %5.0f |", c.convT(g, p)/3600, c.convWh(g, p)); end
    end
    s = s + sprintf(" %5.2f %5.2f %5.2f %5.2f | %5.1f %5.1f %5.1f %5.1f", R.finalErr_pct(g, :), R.initErr_pct(g, :));
    if any(~isnan(c.leftT(g, :))), s = s + "  (left band after converging: " + strjoin(c.names(~isnan(c.leftT(g, :))), ",") + ")"; end
    fprintf("%s\n", s);
end
fprintf("Table nodes with weighted count >= %d:\n", minCount);
for k = 1:3
    n = R.nodes.(nm(k));
    fprintf("  %-4s %3d nodes: median |error| %.2f %%, 90th pct %.2f %%, max %.2f %%, within 1 %%: %.0f %%\n", ...
        nm(k), n.n, n.medAbs, n.p90Abs, n.maxAbs, 100*n.within1pct);
end
end
