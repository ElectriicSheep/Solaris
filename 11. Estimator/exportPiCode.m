%% exportPiCode.m
% Regenerates the estimator C code (11. Estimator/estimator.slx) and copies it to
% 10. CAN/pi/gen for building on the Pi.
r = currentProject().RootFolder;
slbuild("estimator");
src = fullfile(Simulink.fileGenControl("getConfig").CodeGenFolder, "estimator_ert_rtw");
dst = fullfile(r, "10. CAN", "pi", "gen");
f = [dir(fullfile(src, "*.c")); dir(fullfile(src, "*.h"))];
f = f(~strcmp({f.name}, "ert_main.c"));            % bmsadv.c is the main program
for k = 1:numel(f), copyfile(fullfile(src, f(k).name), dst); end
fprintf("%d files copied to %s\n", numel(f), dst);
