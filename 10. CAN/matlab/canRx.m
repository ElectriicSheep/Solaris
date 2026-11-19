function adv = canRx(data, isNew, Ts, tStale)
%CANRX  Advisory frames from the Pi (UDP) -> ADV_bus (10. CAN/solarisCan.dbc).
%   adv = canRx(data, isNew, Ts, tStale)
%   data    144x1 uint8: 9 Linux struct can_frame records (16 bytes: can_id LE, length,
%           3 pad, 8 payload) - ADV_Status, ADV_PackEstimates, ADV_PowerEnergy,
%           ADV_CurrentLimits, ADV_AfeStatus, ADV_GroupSoc mux 0-3 (any order; unknown ids ignored)
%   isNew   true when a new datagram arrived this step (UDP Receive status)
%   Ts      call period, s (CAN_Ts)
%   tStale  ADV_tStale, s: fresh = heartbeat changed within this time
%   Values are held between datagrams; raw all-ones ("not available") decodes to NaN.
    persistent a lastHb tHb tRx
    S = solarisCanDb();
    if isempty(a)
        a = struct("heartbeat", 0, "fresh", false, "valid", false, "socValid", false, ...
            "sohValid", false, "sopValid", false, "soeValid", false, "inputsStale", false, ...
            "estimatorSet", 0, "inputAge", NaN, "framesMissed", 0, "rxAge", NaN, ...
            "socMin", NaN, "socMax", NaN, "socSigma", NaN, "sohQ", NaN, "sohR", NaN, ...
            "sopDchg", NaN, "sopChg", NaN, "soeWh", NaN, "soe", NaN, "iDchgMax", NaN, ...
            "iChgMax", NaN, "horizon", NaN, "socGroup", NaN(13, 1), ...
            "afeState", 0, "safetyA", 0, "safetyB", 0, "safetyC", 0, "fetStatus", 0, "vStack", NaN, "iPack", NaN);
        lastHb = -1;  tHb = inf;  tRx = inf;
    end
    tHb = tHb + Ts;  tRx = tRx + Ts;
    if isNew
        tRx = 0;
        for k = 0:numel(data) / 16 - 1
            i = 16 * k;
            id = typecast(data(i+1:i+4), "uint32");
            d = data(i+9:i+16);
            if id == S.ADV_Status.id
                hb = canGet(d, S.ADV_Status.Heartbeat);
                if hb ~= lastHb, tHb = 0; lastHb = hb; end
                a.heartbeat = hb;
                a.valid = canGet(d, S.ADV_Status.Valid) > 0;
                a.socValid = canGet(d, S.ADV_Status.SocValid) > 0;
                a.sohValid = canGet(d, S.ADV_Status.SohValid) > 0;
                a.sopValid = canGet(d, S.ADV_Status.SopValid) > 0;
                a.soeValid = canGet(d, S.ADV_Status.SoeValid) > 0;
                a.inputsStale = canGet(d, S.ADV_Status.InputsStale) > 0;
                a.estimatorSet = canGet(d, S.ADV_Status.EstimatorSet);
                a.inputAge = canGet(d, S.ADV_Status.InputAge) / 1000;
                a.framesMissed = canGet(d, S.ADV_Status.FramesMissed);
                a.afeState = canGet(d, S.ADV_Status.AfeState);
            elseif id == S.ADV_PackEstimates.id
                a.socMin = na(d, S.ADV_PackEstimates.SocMin) / 100;
                a.socMax = na(d, S.ADV_PackEstimates.SocMax) / 100;
                a.socSigma = na(d, S.ADV_PackEstimates.SocSigma) / 100;
                a.sohQ = na(d, S.ADV_PackEstimates.SohCapacity) / 100;
                a.sohR = na(d, S.ADV_PackEstimates.SohResistance) / 100;
            elseif id == S.ADV_PowerEnergy.id
                a.sopDchg = na(d, S.ADV_PowerEnergy.SopDischarge);
                a.sopChg = na(d, S.ADV_PowerEnergy.SopCharge);
                a.soeWh = na(d, S.ADV_PowerEnergy.SoeEnergy);
                a.soe = na(d, S.ADV_PowerEnergy.SoePercent) / 100;
            elseif id == S.ADV_CurrentLimits.id
                a.iDchgMax = na(d, S.ADV_CurrentLimits.IDischargeMax);
                a.iChgMax = na(d, S.ADV_CurrentLimits.IChargeMax);
                a.horizon = canGet(d, S.ADV_CurrentLimits.Horizon);
            elseif id == S.ADV_AfeStatus.id
                a.safetyA = canGet(d, S.ADV_AfeStatus.SafetyStatusA);
                a.safetyB = canGet(d, S.ADV_AfeStatus.SafetyStatusB);
                a.safetyC = canGet(d, S.ADV_AfeStatus.SafetyStatusC);
                a.fetStatus = canGet(d, S.ADV_AfeStatus.FetStatus);
                a.vStack = canGet(d, S.ADV_AfeStatus.StackVoltage);
                a.iPack = canGet(d, S.ADV_AfeStatus.Current);
            elseif id == S.ADV_GroupSoc.id
                mux = canGet(d, S.ADV_GroupSoc.ADV_GroupSoc_Mux);
                for j = 0:3
                    g = 4 * mux + j + 1;
                    if g <= 13, a.socGroup(g) = na(d, S.ADV_GroupSoc.GroupSoc(g, :)) / 100; end
                end
            end
        end
    end
    a.fresh = tHb < tStale;
    a.rxAge = tRx;
    adv = a;
end

function v = na(d, spec)
% physical value, NaN when raw is all ones (not available)
    v = canGet(d, spec);
    if (v - spec(6)) / spec(5) >= 2^spec(2) - 1, v = NaN; end
end
