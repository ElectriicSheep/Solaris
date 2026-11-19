function L = ecmGetLog(out, t0)
%ECMGETLOG Logged signals of one ecmOffline run as N x 13 matrices (rows = time).
%   L = ecmGetLog(out)        times from 0 at ECM.TsLog
%   L = ecmGetLog(out, t0)    times offset by t0 (continued runs)
if nargin < 2, t0 = 0; end
% clearer names
L = struct("z", out.t_z, "v", out.t_v, "T", out.t_T, "r0", out.t_r0, "r1", out.t_r1, ...
    "tau", out.t_tau, "Wh", out.t_Wh, "i", out.t_i, "mode", out.t_mode, ...
    "zh", out.e_zh, "v1h", get3(out.e_v1h), "r0e", get3(out.e_r0), "r1e", get3(out.e_r1), ...
    "taue", get3(out.e_tau), "Qe", get3(out.e_Q), "r0Rls", get3(out.e_r0Rls), ...
    "r1Rls", get3(out.e_r1Rls), "tauRls", get3(out.e_tauRls), ...
    "Q", out.t_Q, "sohq", out.t_sohq, "sohr", out.t_sohr, "efc", out.t_efc, "cycle", out.t_cycle);
n = size(L.z, 1);
if isprop(out, "t_time") || any(strcmp(out.who, "t_time"))
    L.t = out.t_time(:);
else
    L.t = t0 + (0:n-1)' * evalin("base", "ECM.TsLog");
end
for f = ["tabR0" "tabR1" "tabTau" "cntR0" "cntR1" "cntTau"]
    s = out.(f);
    L.(f) = s.signals.values(:, :, :, end);
end
end

function x = get3(x)
if ndims(x) == 3, x = permute(x, [3 1 2]); end
end

