function frames = canTx(b, lim)
%CANTX  BMS emulator -> CAN: one measurement set as 13 frames (10. CAN/bmsCan.dbc), for UDP.
%   frames = canTx(b, lim)
%   b       BMS_outBus (the BMS outputs, incl. b.meas: measurements with plausibility)
%   lim     CAN_bmsLim: pack limits for f_PackLimits (placeholders)
%   frames  208x1 uint8: 13 Linux struct can_frame records of 16 bytes each:
%           bytes 1-4 can_id (little-endian), 5 length (8), 6-8 zero, 9-16 payload.
%           All zero while the BMS is OFF (a real BMS that is off sends nothing; the
%           Pi bridge drops frames with can_id 0).
%   Frames: f_BmsState, f_PackLimits, f_PackValuesP0, f_PackStateEstimation,
%           f_CellVoltages mux 0-3 (4 groups each), f_CellTemperatures mux 0-4 (6 sensors each).
%   Conventions: one foxBMS "cell" = one 7P group; current discharge positive (as the BMS);
%   temperatures in whole degC (foxBMS resolution); invalid flag 1 = channel not plausible.
    S = bmsCanDb();
    nF = 13;  frames = zeros(16 * nF, 1, "uint8");
    if b.state == BMS_state.OFF
        return
    end
    k = 0;
    m = b.meas;  nG = numel(m.vGroup);  nT = numel(m.tSensor);

    % f_BmsState: foxBMS states 1 INITIALIZATION, 7 NORMAL, 10 ERROR
    d = zeros(8, 1, "uint8");  st = 1;
    if b.state == BMS_state.NORMAL, st = 7; elseif b.state == BMS_state.ERROR, st = 10; end
    d = canPut(d, S.f_BmsState.BmsState, st);
    d = canPut(d, S.f_BmsState.NumberOfConnectedStrings, double(b.contactorCmd));
    d = canPut(d, S.f_BmsState.GeneralError, double(b.state == BMS_state.ERROR));
    d = canPut(d, S.f_BmsState.GeneralWarning, double(any(b.diag.level > 0)));
    [frames, k] = add(frames, k, S.f_BmsState.id, d);

    % f_PackLimits (placeholders, CAN_bmsLim)
    d = zeros(8, 1, "uint8");
    d = canPut(d, S.f_PackLimits.MaximumDischargeCurrent, lim.iDchg);
    d = canPut(d, S.f_PackLimits.MaximumChargeCurrent, lim.iChg);
    d = canPut(d, S.f_PackLimits.MaximumDischargePower, lim.pDchg / 1000);
    d = canPut(d, S.f_PackLimits.MaximumChargePower, lim.pChg / 1000);
    d = canPut(d, S.f_PackLimits.MaximumBatteryVoltage, lim.vMax);
    d = canPut(d, S.f_PackLimits.MinimumBatteryVoltage, lim.vMin);
    [frames, k] = add(frames, k, S.f_PackLimits.id, d);

    % f_PackValuesP0
    vBat = sum(m.vGroup);  vBus = vBat * double(b.contactorCmd);
    d = zeros(8, 1, "uint8");
    d = canPut(d, S.f_PackValuesP0.Current, m.iPack);
    d = canPut(d, S.f_PackValuesP0.BatteryVoltage, vBat);
    d = canPut(d, S.f_PackValuesP0.BusVoltage, vBus);
    d = canPut(d, S.f_PackValuesP0.Power, vBat * m.iPack / 1000);
    [frames, k] = add(frames, k, S.f_PackValuesP0.id, d);

    % f_PackStateEstimation: the BMS's own SOC / SOH (SOE not computed by this BMS: 0)
    d = zeros(8, 1, "uint8");
    d = canPut(d, S.f_PackStateEstimation.MinimumSoc, 100 * min(b.socGroup));
    d = canPut(d, S.f_PackStateEstimation.MaximumSoc, 100 * max(b.socGroup));
    d = canPut(d, S.f_PackStateEstimation.Soh, 100 * b.sohPack);
    [frames, k] = add(frames, k, S.f_PackStateEstimation.id, d);

    % f_CellVoltages, mux 0-3: groups 4*mux+1 .. 4*mux+4 (mV); groups > 13 flagged invalid
    for mux = 0:3
        d = zeros(8, 1, "uint8");
        d = canPut(d, S.f_CellVoltages.f_CellVoltages_Mux, mux);
        for j = 0:3
            g = 4 * mux + j + 1;  v = 0;  bad = 1;
            if g <= nG, v = 1000 * m.vGroup(g);  bad = double(~m.vValid(g)); end
            d = canPut(d, S.f_CellVoltages.CellVoltage(g, :), v);
            d = canPut(d, S.f_CellVoltages.CellVoltage_invalidFlag(g, :), bad);
        end
        [frames, k] = add(frames, k, S.f_CellVoltages.id, d);
    end

    % f_CellTemperatures, mux 0-4: sensors 6*mux+1 .. 6*mux+6 (degC); sensors > 26 invalid
    for mux = 0:4
        d = zeros(8, 1, "uint8");
        d = canPut(d, S.f_CellTemperatures.f_CellTemperatures_Mux, mux);
        for j = 0:5
            s = 6 * mux + j + 1;  t = 0;  bad = 1;
            if s <= nT, t = m.tSensor(s) - 273.15;  bad = double(~m.tValid(s)); end
            d = canPut(d, S.f_CellTemperatures.CellTemperature(s, :), t);
            d = canPut(d, S.f_CellTemperatures.CellTemperature_invalidFlag(s, :), bad);
        end
        [frames, k] = add(frames, k, S.f_CellTemperatures.id, d);
    end
end

function [frames, k] = add(frames, k, id, d)
    i = 16 * k;
    frames(i+1:i+4) = typecast(uint32(id), "uint8");   % little-endian on x86 and ARM
    frames(i+5) = uint8(8);
    frames(i+9:i+16) = d;
    k = k + 1;
end

