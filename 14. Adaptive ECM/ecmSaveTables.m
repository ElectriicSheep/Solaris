function S = ecmSaveTables(L, file)
%ECMSAVETABLES Saves the estimator's tables, counts and capacity at the end of a run
% (a log from ecmGetLog) for use as the starting point of a later run:
%   ecmParams(InitTables=load(file).S)
if nargin < 2
    file = fullfile(fileparts(fileparts(mfilename("fullpath"))), "work", "ecmTables.mat");
end
S.r0 = L.tabR0; S.r1 = L.tabR1; S.tau = L.tabTau;
S.count = cat(4, L.cntR0, L.cntR1, L.cntTau);
S.Q = L.Qe(end, :);
S.savedAt = datetime("now");
S.simTime_s = L.t(end);
save(file, "S");
S.file = string(file);
end
