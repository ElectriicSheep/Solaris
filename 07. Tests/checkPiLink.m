%% checkPiLink.m
% Live SITL test: Simscape plant + BQ76952 emulator (Simulink, PC) <-> solaris_host on the Pi
% (13. Pi) over UDP, paced at real time. Needs on the Pi:  ./solaris_host --sitl 192.168.50.1
% (delete soc_record.txt first so the Pi starts from OCV).
%   Run 1, 60 s, CYCLE A load: the Pi identifies the chip, reads it every 100 ms, runs the
%     estimator and returns ADV frames. Checks: advisory fresh and valid; the Pi's view of the
%     chip (stack voltage, current, FET status) matches the emulator's; the Pi's SOC follows the
%     true SOC (change over the run within 0.05 %; the starting offset is reported, not judged:
%     the chip closes its FETs at once, so the Pi initialises from OCV under load).
%   Run 2, 20 s, COV injected on group 5 (+0.6 V as seen by the chip): the Pi reports Safety
%     Status A bit 3 (COV) and the CHG FET off, while discharge continues.
% PI_link is set to 1 in bmsPlatform.sldd for the runs and restored to 0 afterwards.

runCheck();

function runCheck()
    mdl = "bmsTestPlatform";  load_system(mdl);
    dd = Simulink.data.dictionary.open("bmsPlatform.sldd");
    e = getEntry(getSection(dd, "Design Data"), "PI_link");
    restore = onCleanup(@() setLink(dd, e, 0));
    setLink(dd, e, 1);
    base = Simulink.SimulationInput(mdl).setModelParameter("EnablePacing", "on", "PacingRate", "1");
    pass = true;

    % ---- run 1: nominal ----
    in = base.setModelParameter("StopTime", "60").setVariable("LOAD_profile", 3);
    tic;  [~, out] = evalc("sim(in)");  wall = toc;
    save(fullfile(currentProject().RootFolder, "work", "pilink1.mat"), "out");
    adv = out.logsout.get("adv").Values;  tr = out.logsout.get("truth").Values;  afe = out.logsout.get("afe").Values;
    t = adv.socMin.Time;  fresh = adv.fresh.Data(:);  valid = adv.valid.Data(:);
    fprintf("\n=== 1. nominal, 60 s simulated, %.0f s wall (paced)\n", wall);
    k0 = find(fresh & valid, 1);
    if isempty(k0)
        fprintf("   advisory never fresh and valid: is solaris_host running on the Pi?\nOverall: FAIL\n");  return
    end
    ok = t >= t(k0) + 1;
    fprintf("   first fresh+valid advisory at %.1f s; after that fresh %.1f %%, valid %.1f %%; cycles missed (Pi) %g\n", ...
        t(k0), 100*mean(fresh(ok)), 100*mean(valid(ok)), adv.framesMissed.Data(end));
    pass = pass && mean(fresh(ok)) > 0.99 && mean(valid(ok)) > 0.99;
    % the Pi's view of the chip vs the plant: each advisory sample reports a chip reading taken up
    % to ~0.3 s (simulated) earlier (Pi cycle 0.1 s + advisory period 0.1 s + link), so it is
    % compared with the plant over [t - 0.3 s, t] (closest value in that window)
    tt = tr.iPack.Time;  iT = tr.iPack.Data(:);  vT = sum(rows(tr.vGroup), 2);
    ta = t(ok);  iA = adv.iPack.Data(ok);  vA = adv.vStack.Data(ok);  dI = 0;  dV = 0;
    for j = 1:numel(ta)
        w = tt >= ta(j) - 0.3 & tt <= ta(j);
        dI = max(dI, min(abs(iT(w) - iA(j))));  dV = max(dV, min(abs(vT(w) - vA(j))));
    end
    fets = unique(adv.fetStatus.Data(ok))';
    fprintf("   Pi's view of the chip: max |I - plant| %.3f A, max |Vstack - plant| %.3f V (limits 0.02 A, 0.05 V: chip and CAN resolution), FET status %s\n", dI, dV, mat2str(fets));
    pass = pass && isequal(fets, 5) && dI <= 0.02 && dV <= 0.05;
    % SOC: offset at start, tracking over the run
    sP = adv.socGroup.Data(ok, :);  sT = interp1(tr.socGroup.Time, rows(tr.socGroup), t(ok), "previous");
    off0 = sP(1, :) - sT(1, :);  dP = sP(end, :) - sP(1, :);  dT = sT(end, :) - sT(1, :);
    fprintf("   SOC offset at start (OCV under load) %.2f..%.2f %%; change over the run: Pi %.3f %%, true %.3f %%, max |diff| %.3f %% (limit 0.05 %%)\n", ...
        100*min(off0), 100*max(off0), 100*mean(dP), 100*mean(dT), 100*max(abs(dP - dT)));
    pass = pass && max(abs(dP - dT)) <= 0.0005;

    % ---- run 2: COV ----
    v = zeros(13, 1);  v(5) = 0.6;
    in = base.setModelParameter("StopTime", "20").setVariable("LOAD_profile", 1).setVariable("AFE_vOffset", v);
    [~, out] = evalc("sim(in)");
    save(fullfile(currentProject().RootFolder, "work", "pilink2.mat"), "out");
    adv = out.logsout.get("adv").Values;  afe = out.logsout.get("afe").Values;
    t = adv.safetyA.Data;  ta = adv.safetyA.Time;
    tChip = afe.chg.Time(find(~afe.chg.Data(:) & afe.chg.Time > 0.05, 1));
    kPi = find(bitand(double(adv.safetyA.Data(:)), 8) & ~bitand(double(adv.fetStatus.Data(:)), 1) & adv.fresh.Data(:), 1);
    tPi = ta(kPi);  if isempty(tPi), tPi = NaN; end
    iEnd = adv.iPack.Data(end);
    fprintf("\n=== 2. COV on group 5\n   emulator CHG off at %.2f s; Pi reports COV + CHG off at %.2f s; discharge current at end (Pi) %.2f A\n", tChip, tPi, iEnd);
    pass = pass && ~isnan(tPi) && tPi - tChip < 1.0 && iEnd > 20;
    fprintf("\nOverall: %s\n", string(ifelse(pass, "PASS", "FAIL")));
end
function d = rows(ts)
    % logged vector signal as time x elements (the plant logs 13 x 1 x N)
    d = ts.Data;
    if ndims(d) == 3, d = permute(d, [3 1 2]); end
end
function setLink(dd, e, v)
    p = getValue(e);  p.Value = v;  setValue(e, p);  saveChanges(dd);
end
function o = ifelse(c, a, b), if c, o = a; else, o = b; end, end
