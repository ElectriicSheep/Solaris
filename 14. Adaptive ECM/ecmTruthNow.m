function T = ecmTruthNow(P, sohr, name)
%ECMTRUTHNOW True table (estimator grid) for parameter name ("r0" "r1" "tau") at the
% resistance state of health sohr (1 x 13): R = R_new / SOHr; tau1 is not aged.
T = P.truth.(name);
if name ~= "tau", T = T ./ reshape(sohr, 1, 1, []); end
end
