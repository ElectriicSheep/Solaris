%% checkPiLink.m
% Live test of the CAN link to the Raspberry Pi advisory estimator (10. CAN/pi):
% platform with CAN_link = 1 (UDP to 192.168.50.2), paced at real time, CYCLE A load.
% Needs on the Pi:  ./canudp -i vcan0 -p 192.168.50.1   and   ./bmsadv -i vcan0
% Both the BMS and the Pi start without a valid SOC record (BMS: HW_nvm default; Pi: delete
% ~/bmsadv/soc_record.txt first), so both initialise from OCV and run the same SE logic:
% the advisory SOC should follow the BMS's within the CAN resolution (0.01 %) and a few
% steps of link latency. Checks: advisory fresh and valid after start-up, heartbeat
% advancing, |SOC_adv - SOC_bms| small, ARB uses the advisory SOC.
% CAN_link is set to 1 in bmsPlatform.sldd for the run and restored to 0 afterwards.

runCheck(60);

function runCheck(T)
    mdl = "bmsTestPlatform";  load_system(mdl);
    dd = Simulink.data.dictionary.open("bmsPlatform.sldd");
    e = getEntry(getSection(dd, "Design Data"), "CAN_link");
    restore = onCleanup(@() setLink(dd, e, 0));
    setLink(dd, e, 1);
    in = Simulink.SimulationInput(mdl).setModelParameter("StopTime", string(T), ...
        "EnablePacing", "on", "PacingRate", "1").setVariable("LOAD_profile", 3);
    tic;  [~, out] = evalc("sim(in)");  wall = toc;
    fprintf("\n=== live link, %d s simulated, %.0f s wall (paced at real time)\n", T, wall);
    save(fullfile(currentProject().RootFolder, "work", "pilink.mat"), "out");   % for inspection
    adv = out.logsout.get("adv").Values;  arb = out.logsout.get("arb").Values;
    t = adv.socMin.Time;  sAdv = adv.socMin.Data(:);  sBms = arb.socBms.Data(:);
    fresh = adv.fresh.Data(:);  valid = adv.valid.Data(:);  hb = adv.heartbeat.Data(:);
    use = arb.useAdv.Data(:);  rxAge = adv.rxAge.Data(:);
    k0 = find(fresh & valid, 1);
    if isempty(k0)
        fprintf("   advisory never fresh and valid: link or Pi programs not running?\n");
        fprintf("   max heartbeat %g, last rxAge %.1f s\nOverall: FAIL\n", max(hb), rxAge(end));  return
    end
    ok = t >= t(k0) + 1;                                   % 1 s after the first valid output
    d = abs(sAdv(ok) - sBms(ok));
    fprintf("   first fresh+valid advisory at %.1f s (BMS powered at ~0.9 s)\n", t(k0));
    fprintf("   after that: fresh %.1f %% of steps, valid %.1f %%, ARB used advisory %.1f %%\n", ...
        100*mean(fresh(ok)), 100*mean(valid(ok)), 100*mean(use(ok)));
    fprintf("   heartbeat advanced %d times; max datagram age %.2f s; frames missed (Pi) %g\n", ...
        sum(diff(hb(ok)) ~= 0), max(rxAge(ok)), adv.framesMissed.Data(end));
    fprintf("   SOC  BMS %.3f %% -> %.3f %% | advisory %.3f %% -> %.3f %%\n", 100*sBms(find(ok,1)), 100*sBms(end), 100*sAdv(find(ok,1)), 100*sAdv(end));
    fprintf("   max |SOC_adv - SOC_bms| = %.3f %% (limit 0.05 %%: resolution + latency)\n", 100*max(d));
    pass = mean(fresh(ok)) > 0.99 && mean(valid(ok)) > 0.99 && mean(use(ok)) > 0.99 && max(d) <= 0.0005;
    fprintf("\nOverall: %s\n", string(ifelse(pass, "PASS", "FAIL")));
end
function setLink(dd, e, v)
    p = getValue(e);  p.Value = v;  setValue(e, p);  saveChanges(dd);
end
function o = ifelse(c, a, b), if c, o = a; else, o = b; end, end
