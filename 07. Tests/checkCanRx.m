%% checkCanRx.m
% Checks canRx.m (PC side) on an advisory datagram produced by the Pi program solaris_host
% (13. Pi) running against the BQ76952 emulator (12. AFE, bqe_sitl: 13 groups around 80 % SOC,
% 5 A discharge). Expected values decoded independently by cantools: heartbeat 31, valid,
% SocMin 79.66 %, SocMax 81.79 %, group 1 79.66 %, group 13 81.79 %, both FETs on (FetStatus 5,
% AfeState 3), no safety faults, stack 51.71 V, current 5.00 A; SOP / SOE / SOH not available.

hexStr = "80030000080000001f0300000300000081030000080000001edffcf7ffffff038203000008000000ffffffffffffff3f8303000008000000ffffff00000000008503000008000000000000053314f4018403000008000000001edfcc77f4697d8403000008000000016d1fe037f9757e840300000800000002b0dff067fda57f840300000800000003f3dfffffffffff";
data = uint8(hex2dec(reshape(char(hexStr), 2, []).'));
clear canRx                                   % reset its persistent state
adv = canRx(data, true, 0.1, 1);
c = [adv.heartbeat == 31, adv.valid, adv.socValid, ~adv.sopValid, adv.fresh, ...
     abs(adv.socMin - 0.7966) < 1e-9, abs(adv.socMax - 0.8179) < 1e-9, ...
     abs(adv.socGroup(1) - 0.7966) < 1e-9, abs(adv.socGroup(13) - 0.8179) < 1e-9, ...
     adv.fetStatus == 5, adv.afeState == 3, adv.safetyA == 0, adv.safetyB == 0, ...
     abs(adv.vStack - 51.71) < 1e-9, abs(adv.iPack - 5.00) < 1e-9, ...
     isnan(adv.sopDchg), isnan(adv.soe), isnan(adv.sohQ), isnan(adv.socSigma)];
fprintf("heartbeat %d valid %d | socMin %.4f socMax %.4f | g1 %.4f g13 %.4f | FET %d AFE %d safety %d/%d | %.2f V %.2f A | sop %g\n", ...
    adv.heartbeat, adv.valid, adv.socMin, adv.socMax, adv.socGroup(1), adv.socGroup(13), adv.fetStatus, adv.afeState, adv.safetyA, adv.safetyB, adv.vStack, adv.iPack, adv.sopDchg);
for k = 1:11, adv = canRx(data, false, 0.1, 1); end      % no new data for 1.1 s -> stale
c(end+1) = ~adv.fresh;
fprintf("after 1.1 s without data: fresh %d (expected 0)\n", adv.fresh);
fprintf("Overall: %s\n", string(ifelse(all(c), "PASS", "FAIL")));
clear canRx
function o = ifelse(cnd, a, b), if cnd, o = a; else, o = b; end, end
