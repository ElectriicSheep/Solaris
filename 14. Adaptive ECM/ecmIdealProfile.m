function [i, info] = ecmIdealProfile(Ts, opts)
%ECMIDEALPROFILE Synthetic discharge current designed for parameter identification
% ("ideal excitation"), for comparison with marine loading (CYCLE A).
%
%   i = ecmIdealProfile(0.1)   one pass (default 3600 s), looped by the load schedule
%
% Same average current and same peak as CYCLE A, so the comparison is at equal charge
% throughput and equal peak stress. Two parts on top of the average:
%   multisine   30 log-spaced harmonics of 1/T between 1/T and 0.2 Hz with Schroeder
%               phases (low crest factor): excites the RC branch (tau1 30-80 s,
%               corner frequencies 2-5 mHz) evenly across its band
%   APRBS       random levels held for 2-60 s (log-uniform): sharp steps for R0 and
%               step responses of the RC branch
% Short negative excursions (charge pulses, to -3 A) are allowed: current of both signs
% separates R0 and R1 from the OCV better. The result is clipped to [-3, peak] and the
% average is restored afterwards.
arguments
    Ts (1,1) double = 0.1
    opts.T (1,1) double = 3600
    opts.Seed (1,1) double = 7
    opts.Std (1,1) double = NaN     % default: CYCLE A's standard deviation
end
here = fileparts(mfilename("fullpath"));
cyc = load(fullfile(fileparts(here), "01. LoadProfiles", "marineCycle_a.mat"), "marine_cycle").marine_cycle(2, :);
iMean = mean(cyc);  iPeak = max(cyc);
if isnan(opts.Std), opts.Std = std(cyc); end
s = RandStream("mt19937ar", "Seed", opts.Seed);
N = round(opts.T / Ts);  t = (0:N-1)' * Ts;
% multisine
f0 = 1 / opts.T;
k = unique(round(logspace(0, log10(0.2 / f0), 30)));
ph = -pi * k .* (k - 1) / numel(k);                 % Schroeder phases
ms = sum(cos(2*pi*f0*t*k + ph), 2);
ms = ms / std(ms);
% APRBS
ap = zeros(N, 1); n = 1;
while n <= N
    hold = round(exp(log(2) + (log(60) - log(2)) * rand(s)) / Ts);
    ap(n:min(n+hold-1, N)) = randn(s);
    n = n + hold;
end
ap = ap / std(ap);
x = 0.5 * ms + 0.866 * ap;                          % equal variance shares
x = x / std(x) * opts.Std;
i = iMean + x;
for it = 1:20                                       % clip, restore the mean
    i = min(max(i, -3), iPeak);
    i = i + (iMean - mean(i));
end
i = min(max(i, -3), iPeak);
info = struct("mean", mean(i), "std", std(i), "max", max(i), "min", min(i), ...
    "cycleA_mean", iMean, "cycleA_std", std(cyc), "cycleA_max", iPeak, "nHarmonics", numel(k));
end
