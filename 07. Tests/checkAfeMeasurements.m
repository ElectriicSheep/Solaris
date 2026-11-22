function results = checkAfeMeasurements()
%CHECKAFEMEASUREMENTS Verify measured BQ76952 register values vs plant truth.
%
% Repository: ElectriicSheep/Solaris, main, 2026-11-20.
%
% Prerequisite (one-time, in Simulink):
%   In bmsTestPlatform/SM_bms/AFE, select the 144-byte uint8 signal
%   connected to the `snap` output of bqe_step(), enable signal logging,
%   and set its signal name to "afeSnapshot". Keep the signal internal;
%   do not connect the plant truth bus to the host estimator.
%
% This test makes no permanent changes to plant, AFE, dictionary, or model.
% The current emulator has register quantisation but does not model ADC
% random noise or actual hardware conversion latency.
%
% Run after opening modularBMS.prj and running defineInterfaces and
% defineParameters as for checkAfe.m.
%
% Usage:
%   results = checkAfeMeasurements;
%
% Expected SI conventions: plant iPack DISCHARGE-positive; BQ CC2 CHARGE-positive.

    mdl = 'bmsTestPlatform';
    load_system(mdl);

    % Keep the test independent of the Pi SITL link.
    dd = Simulink.data.dictionary.open('bmsPlatform.sldd');
    sec = getSection(dd, 'Design Data');
    piLink = getValue(getEntry(sec, 'PI_link'));
    assert(piLink.Value == 0, ...
        'Set PI_link = 0 in bmsPlatform.sldd before running this test.');

    % Sensor placement exactly as defined in the repository.
    tm = getValue(getEntry(sec, 'AFE_thermMap'));
    tb = getValue(getEntry(sec, 'AFE_thermBias'));
    thermMap = double(tm.Value);      % [9 x 91]
    thermBias = double(tb.Value(:));  % [9 x 1] K
    thermPins = [4, 6, 7, 8, 9, 1, 2]; % thermistors 1..7, 1-based pin numbers

    assert(isequal(size(thermMap), [9 91]), 'Unexpected AFE_thermMap dimensions.');
    assert(numel(thermBias) == 9, 'Unexpected AFE_thermBias dimensions.');

    % Deterministic, no injected offsets, below protection thresholds.
    in = Simulink.SimulationInput(mdl) ...
        .setModelParameter('StopTime', '3') ...
        .setVariable('LOAD_profile', 1) ...
        .setVariable('LOAD_iConst', 5) ...
        .setVariable('AFE_vOffset', zeros(13,1)) ...
        .setVariable('AFE_tOffset', zeros(7,1));
    out = sim(in);

    % Ground truth already logged by the existing platform.
    truth = out.logsout.get('truth');
    assert(~isempty(truth), 'Missing logged truth bus (out.logsout.get("truth")).');
    truth = truth.Values;
    [tV, vGroup] = samples(truth.vGroup, 13);
    [tI, iPack]  = samples(truth.iPack, 1);
    [tT, tCell]  = samples(truth.tCell, 91);

    % Require raw device registers: don't substitute a processed advisory bus.
    snapshotSignal = out.logsout.get('afeSnapshot');
    if isempty(snapshotSignal)
        error(['Missing 144-byte uint8 logged signal "afeSnapshot". ' ...
            'Open bmsTestPlatform/SM_bms/AFE and enable signal logging on ' ...
            'the snap output of bqe_step(). Rename that signal afeSnapshot. ' ...
            'Do not modify the plant or the C emulator.']);
    end
    [tSnap, snapDouble] = samples(snapshotSignal.Values, 144);
    snap = uint8(snapDouble);
    assert(all(snap(:,1) == uint8('B')) && all(snap(:,2) == uint8('Q')) && ...
           all(snap(:,3) == uint8('7')) && all(snap(:,4) == uint8('6')), ...
           'Invalid BQ76 snapshot header. Check raw-signal selection.');

    % Exclude start-up and require at least 10 samples.
    keep = tSnap >= 0.10;
    tSnap = tSnap(keep);
    snap = snap(keep,:);
    assert(numel(tSnap) >= 10, 'Not enough samples after startup.');

    % The snapshot layout is:
    %  1..4 magic, 5..8 sequence, 9..12 ack, 13..16 t_ms,
    %  17..144 direct-command register addresses 0x00..0x7F.
    n = size(snap,1);
    vBms = zeros(n, 13);
    for g = 1:13
        reg = hex2dec('14') + 2*(g-1);   % CELL1 = 0x14, ... CELL13 = 0x2C
        vBms(:,g) = regSigned16(snap, reg) * 1e-3;
    end
    vStackBms = regSigned16(snap, hex2dec('34')) * 1e-2; % DA_CONFIG=0x06
    iBms = -regSigned16(snap, hex2dec('3A')) * 1e-2;      % convert to discharge-positive

    tBms = zeros(n,7);
    for k = 1:7
        reg = hex2dec('6A') + 2*(thermPins(k)-1);
        tBms(:,k) = regSigned16(snap, reg) * 0.1;  % Kelvin
    end

    % Align to snapshot timestamps; truth has the same model clock.
    % A persistent 10 ms lag will show up in transient tests; do not silently
    % compensate for lag here.
    vRef = interp1(tV, vGroup, tSnap, 'previous', 'extrap');
    iRef = interp1(tI, iPack, tSnap, 'previous', 'extrap');
    cellT = interp1(tT, tCell, tSnap, 'previous', 'extrap');
    pinT = cellT * thermMap.' + thermBias.';  % [N x 9], Kelvin
    tRef = pinT(:,thermPins);

    errorCellV = vBms - vRef;
    errorStackV = vStackBms - sum(vRef,2);
    errorI = iBms - iRef;
    errorT = tBms - tRef;

    % Tolerances include one quantisation LSB and a little numerical margin:
    % cells 1 mV; pack 10 mV; current 10 mA; temperature 0.1 K.
    % Zero offsets and a constant-current test make timing errors small.
    tolerances = struct('cellV', 0.0011, 'stackV', 0.011, ...
                        'currentA', 0.011, 'tempK', 0.11);
    maxima = struct('cellV', max(abs(errorCellV),[],'all'), ...
                    'stackV', max(abs(errorStackV)), ...
                    'currentA', max(abs(errorI)), ...
                    'tempK', max(abs(errorT),[],'all'));
    checks = struct('cellV', maxima.cellV <= tolerances.cellV, ...
                    'stackV', maxima.stackV <= tolerances.stackV, ...
                    'currentA', maxima.currentA <= tolerances.currentA, ...
                    'tempK', maxima.tempK <= tolerances.tempK);

    fprintf('\n=== BQ76952 measurement-fidelity test (3 s, 5 A nominal) ===\n');
    names = {'cellV','stackV','currentA','tempK'};
    units = {'V','V','A','K'};
    for k = 1:numel(names)
        f = names{k};
        verdict = 'PASS';
        if ~checks.(f), verdict = 'FAIL'; end
        fprintf('  %-9s max error = %.6g %-1s (limit %.6g)  %s\n', ...
            f, maxima.(f), units{k}, tolerances.(f), verdict);
    end

    results = struct('passed', all(structfun(@(x) logical(x), checks)), ...
        'maxima', maxima, 'tolerances', tolerances, 'checks', checks, ...
        't', tSnap, 'vRef', vRef, 'vBms', vBms, 'iRef', iRef, 'iBms', iBms, ...
        'tRef', tRef, 'tBms', tBms, 'vStackBms', vStackBms);

    % Readable verification plots, separate from the production model.
    figure('Name', 'BQ76952 AFE measurement fidelity', 'Color', 'w');
    tiledlayout(3,1);
    nexttile;
    plot(tSnap, vRef(:,1), 'LineWidth', 1.2); hold on;
    plot(tSnap, vBms(:,1), '--', 'LineWidth', 1.2); hold off;
    ylabel('Group 1 (V)'); legend('Plant', 'AFE', 'Location', 'best'); grid on;
    nexttile;
    plot(tSnap, iRef, 'LineWidth', 1.2); hold on;
    plot(tSnap, iBms, '--', 'LineWidth', 1.2); hold off;
    ylabel('Pack current (A)'); legend('Plant', 'AFE', 'Location', 'best'); grid on;
    nexttile;
    plot(tSnap, tRef(:,1), 'LineWidth', 1.2); hold on;
    plot(tSnap, tBms(:,1), '--', 'LineWidth', 1.2); hold off;
    ylabel('Thermistor 1 (K)'); xlabel('Time (s)');
    legend('Mapped plant', 'AFE', 'Location', 'best'); grid on;

    if results.passed
        fprintf('Overall: PASS\n');
    else
        warning('Measurement test failed. Check wiring, sampling alignment or register scaling.');
        fprintf('Overall: FAIL\n');
    end
end

function values = regSigned16(snap, reg)
% Little-endian signed two-byte BQ76952 direct-command register.
    lo = double(snap(:, 17 + reg));
    hi = double(snap(:, 18 + reg));
    unsigned = lo + 256 * hi;
    values = unsigned - 65536 * (unsigned >= 32768);
end

function [time, values] = samples(ts, channels)
% Convert logged Simulink timeseries data to [N samples x channels].
    time = double(ts.Time(:));
    d = ts.Data;
    n = numel(time);
    if ismatrix(d)
        if size(d,1) == n && size(d,2) == channels
            values = double(d);
        elseif size(d,2) == n && size(d,1) == channels
            values = double(d.');
        elseif channels == 1 && numel(d) == n
            values = double(d(:));
        else
            error('Logged signal shape %s does not match %d samples and %d channels.', ...
                mat2str(size(d)), n, channels);
        end
    elseif size(d,ndims(d)) == n
        permutation = [ndims(d), 1:(ndims(d)-1)];
        values = reshape(permute(d, permutation), n, []);
        values = double(values);
    else
        error('Unsupported logged signal shape %s.', mat2str(size(d)));
    end
    assert(size(values,2) == channels, ...
        'Expected %d channels, got %d.', channels, size(values,2));
end
