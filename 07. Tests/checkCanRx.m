%% checkCanRx.m
% Checks canRx.m (PC side) on an advisory datagram produced by the Pi program bmsadv
% (10. CAN/pi, generated estimator code) from 20 BMS frame sets: 13 groups at
% 3.725 V + 2 mV steps, 5 A discharge. Expected values decoded independently by cantools:
% heartbeat 24, valid, SocMin 49.98 %, SocMax 53.41 %, group 1 49.98 %, group 13 53.41 %,
% SOP / SOE / SOH not available (NaN).

hexStr = "800300000800000018030000070000008103000008000000865337f5ffffff038203000008000000ffffffffffffff3f8303000008000000ffffff000000000084030000080000000086d3e8043c714f840300000800000001f95305254339518403000008000000026b1422454a0553840300000800000003ddd4ffffffffff";
data = uint8(hex2dec(reshape(char(hexStr), 2, []).'));
clear canRx                                   % reset its persistent state
adv = canRx(data, true, 0.1, 1);
c = [adv.heartbeat == 24, adv.valid, adv.socValid, ~adv.sopValid, adv.fresh, ...
     abs(adv.socMin - 0.4998) < 1e-9, abs(adv.socMax - 0.5341) < 1e-9, ...
     abs(adv.socGroup(1) - 0.4998) < 1e-9, abs(adv.socGroup(13) - 0.5341) < 1e-9, ...
     isnan(adv.sopDchg), isnan(adv.soe), isnan(adv.sohQ), isnan(adv.socSigma)];
fprintf("heartbeat %d valid %d | socMin %.4f socMax %.4f | g1 %.4f g13 %.4f | sop %g soe %g sohQ %g\n", ...
    adv.heartbeat, adv.valid, adv.socMin, adv.socMax, adv.socGroup(1), adv.socGroup(13), adv.sopDchg, adv.soe, adv.sohQ);
% no new data for 1.1 s -> stale
for k = 1:11, adv = canRx(data, false, 0.1, 1); end
c(end+1) = ~adv.fresh;
fprintf("after 1.1 s without data: fresh %d (expected 0)\n", adv.fresh);
fprintf("Overall: %s\n", string(ifelse(all(c), "PASS", "FAIL")));
clear canRx
function o = ifelse(cnd, a, b), if cnd, o = a; else, o = b; end, end
