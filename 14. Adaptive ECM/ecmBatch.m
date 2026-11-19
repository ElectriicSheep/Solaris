function file = ecmBatch(ECM, nCycles, file, opts)
%ECMBATCH Runs N schedule cycles flat out (no plotting) and saves the result for
% replay in EcmConvergenceApp ("Open results").
%
%   f = ecmBatch(ecmParams(Profile="ideal"), 100, "work/ideal100.mat")
%
% Several runs in parallel (process workers, one per run):
%   F = parfeval(parpool("Processes"), @ecmBatch, 1, ECM, 100, "work/a.mat");
%
% Logging: estimates and truth every opts.TsLog s (default 10 s) for the convergence
% clocks; the history kept for display every opts.Decim s (default 60 s); tables
% once per chunk (opts.ChunkHours, default 24 h).
arguments
    ECM struct
    nCycles (1,1) double
    file (1,1) string
    opts.TsLog (1,1) double = 10
    opts.Decim (1,1) double = 60
    opts.ChunkHours (1,1) double = 24
    opts.Resume (1,1) string = ""       % continue from a saved result instead of ECM
end
if opts.Resume ~= ""
    E = EcmEngine.load(opts.Resume);
    E.P.load.nCycles = max(E.H.cycle(end), 0) + nCycles;
    E.done = false;
else
    ECM.TsLog = opts.TsLog;
    ECM.load.nCycles = nCycles;
    E = EcmEngine(ECM, opts.Decim);
end
E.start(Accelerator=true);
c = onCleanup(@() E.stopFastRestart());
while ~E.done
    E.advance(E.tDone + opts.ChunkHours * 3600);
    fprintf("%s: %.0f h simulated, cycle %d, %.0f s wall\n", file, E.tDone/3600, E.H.cycle(end), E.wall);
end
E.save(file);
end
