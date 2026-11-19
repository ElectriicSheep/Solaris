function F = ecmBatchMany(cfgs, nWorkers)
%ECMBATCHMANY Several ecmBatch runs in parallel, one per process worker.
%
%   cfg(1) = struct("P", ecmParams(Profile="cycleA"), "nCycles", 100, "file", "work/marine100.mat");
%   cfg(2) = struct("P", ecmParams(Profile="ideal"),  "nCycles", 100, "file", "work/ideal100.mat");
%   F = ecmBatchMany(cfg);  wait(F);  fetchOutputs(F)   % file names
%
% Each worker uses its own Simulink cache folder (the accelerator build is per worker).
if nargin < 2, nWorkers = min(numel(cfgs), 4); end
pool = gcp("nocreate");
if isempty(pool) || ~isa(pool, "parallel.ProcessPool") || pool.NumWorkers < nWorkers
    delete(gcp("nocreate"));
    pool = parpool("Processes", nWorkers);
end
for k = numel(cfgs):-1:1
    F(k) = parfeval(pool, @runOne, 1, cfgs(k));
end
end

function file = runOne(cfg)
t = getCurrentTask();
cache = fullfile(tempdir, "ecmWorker" + t.ID);
Simulink.fileGenControl("set", "CacheFolder", cache, "CodeGenFolder", cache, "createDir", true);
file = ecmBatch(cfg.P, cfg.nCycles, cfg.file);
end
