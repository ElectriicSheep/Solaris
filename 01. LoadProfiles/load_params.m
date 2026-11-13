%% load_params.m
% Load profiles for the LOAD layer. Run by bmsTestPlatform's InitFcn.
%
% The profiles are stored in the model's code as lookup tables (no files are read
% while running), so they work on the desktop and on the OP5033 alike.
%
% Creates, in the base workspace:
%   LOAD_cycleA     marineCycle_a.mat           (1369 s, played in a loop)
%   LOAD_cycleAext  marineCycle_a_extended.mat  (~28 h, played in a loop)
% each a struct with
%   .i   current samples, row 1 of the file's data, in A (pack, discharge positive),
%        before LOAD_scale
%   .dt  sample interval, s (the files are uniformly sampled at 0.1 s; checked below)
%   .T   duration of one pass, s (= number of samples x dt)
%   .k   platform steps per sample (dt / 0.01 s, a whole number; checked below)
%   .N   platform steps per pass   (number of samples x k)
% The LOAD layer's profile clock counts whole platform steps, and the lookup tables
% use .k and .N, so every sample boundary is exact (no accumulated rounding).
% Row 2 of the files (values 0 to 2) is not used here.
%
% The extended profile is ~1 million samples. It is compiled into the RT-LAB build
% as a constant table (~8 MB); if builds become too slow, drop it from lpFiles.

lpTs    = 0.01;     % s, platform fixed step (cfgHarness FixedStep)
lpFiles = ["marineCycle_a.mat"   "marineCycle_a_extended.mat"];
lpNames = ["LOAD_cycleA"         "LOAD_cycleAext"];

for lpIdx = 1:numel(lpFiles)
    lpData = load(lpFiles(lpIdx), "marine_cycle").marine_cycle;   % rows: time; current; (unused)
    lpT    = lpData(1, :);
    lpDt   = median(diff(lpT));
    assert(abs(lpT(1)) < 1e-9 && all(abs(diff(lpT) - lpDt) < 1e-6), ...
        "%s: expected uniformly sampled data starting at t = 0.", lpFiles(lpIdx));
    lpK    = round(lpDt / lpTs);
    assert(abs(lpDt - lpK*lpTs) < 1e-9, ...
        "%s: sample interval %g s is not a whole number of %g s platform steps.", lpFiles(lpIdx), lpDt, lpTs);
    lpProfile = struct("i", lpData(2, :)', "dt", lpK*lpTs, "T", numel(lpT)*lpK*lpTs, ...
                       "k", lpK, "N", numel(lpT)*lpK);
    assignin("base", lpNames(lpIdx), lpProfile);
end

clear lpTs lpFiles lpNames lpIdx lpData lpT lpDt lpK lpProfile
