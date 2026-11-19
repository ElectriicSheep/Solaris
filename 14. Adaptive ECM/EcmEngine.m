classdef EcmEngine < handle
%ECMENGINE Runs ecmOffline in chunks and keeps a decimated history for display,
% convergence clocks and replay. Used by EcmConvergenceApp (live) and ecmBatch
% (flat out, saved to file, replayed in the app).
%
%   E = EcmEngine(ECM);                 % ECM from ecmParams
%   E.start(Accelerator=true);
%   while ~E.done && E.tDone < 24*3600, E.advance(E.tDone + 1800); end
%   E.save("work/run1.mat");            % E2 = EcmEngine.load("work/run1.mat")
%
% History H (every `decim` seconds of simulated time): t, err (n x 13 x 4, % : R0 R1
% tau1 Q, estimate at the operating point vs truth), z, zh, i, v, T, Wh, mode, cycle,
% efc, sohq, sohr, Q, Qe, plus tabT / tabErr (median |error| of updated table points,
% per chunk). `last` holds the last chunk's tables and counts. `conv` is the
% ecmConvergence clock object (fed at the full logging rate).

    properties
        P                       % parameters (ECM)
        mdl = "ecmOffline"
        op = []                 % operating point to continue from
        tDone = 0               % s simulated
        done = false            % stopped by the cycle limit
        conv
        H
        last = []
        decim = 10              % s, history interval
        wall = 0                % s, wall time spent simulating
    end

    methods
        function obj = EcmEngine(P, decim)
            obj.P = P;
            if nargin > 1, obj.decim = decim; end
            obj.conv = ecmConvergence(0.01, 600);
            z13 = zeros(0, 13);
            obj.H = struct("t", zeros(0, 1), "err", zeros(0, 13, 4), "z", z13, "zh", z13, "i", zeros(0, 1), ...
                "v", z13, "T", z13, "Wh", z13, "mode", zeros(0, 1), "cycle", zeros(0, 1), "efc", z13, ...
                "sohq", z13, "sohr", z13, "Q", z13, "Qe", z13, "tabT", zeros(0, 1), "tabErr", zeros(0, 13, 3), ...
                "tabBias", zeros(0, 13, 3));
        end

        function start(obj, opts)
            arguments
                obj
                opts.Accelerator (1,1) logical = true
            end
            assignin("base", "ECM", obj.P);
            load_system(obj.mdl);
            set_param(obj.mdl, "FastRestart", "off");
            set_param(obj.mdl, "SimulationMode", string(ifelse(opts.Accelerator, "accelerator", "normal")));
            set_param(obj.mdl, "SaveFinalState", "on", "SaveOperatingPoint", "on", ...
                "FinalStateName", "xFinal", "LoadInitialState", "off");
            set_param(obj.mdl, "FastRestart", "on");
        end

        function advance(obj, t1)
            % Simulate from tDone to t1 (or until the cycle limit stops the run).
            assignin("base", "ECM", obj.P);
            in = Simulink.SimulationInput(obj.mdl).setModelParameter("StopTime", string(t1));
            if ~isempty(obj.op), in = in.setInitialState(obj.op); end
            % tunable parameters (e.g. the cycle limit) may change between chunks
            ws = warning("off", "Simulink:SimState:SimStateParameterChecksumMisMatch");
            restoreW = onCleanup(@() warning(ws));
            w = tic;
            out = sim(in);
            obj.wall = obj.wall + toc(w);
            obj.op = out.xFinal;
            L = ecmGetLog(out, obj.tDone);
            if obj.tDone > 0, L = keepAfter(L, obj.conv.tNow); end   % drop samples already logged
            if ~isempty(L.t), obj.ingest(L); end
            tEndSim = obj.op.snapshotTime;
            if tEndSim < t1 - 1e-6, obj.done = true; end
            obj.tDone = tEndSim;
        end

        function stopFastRestart(obj)
            try, set_param(obj.mdl, "FastRestart", "off"); catch, end
        end

        function ingest(obj, L)
            E = cat(3, (L.r0e - L.r0) ./ L.r0, (L.r1e - L.r1) ./ L.r1, (L.taue - L.tau) ./ L.tau, ...
                (L.Qe - L.Q) ./ L.Q);
            obj.conv.add(L.t, E, L.Wh);
            % history: first sample in each decim-second bin not yet in the history
            b = floor(L.t / obj.decim);
            lastBin = -inf; if ~isempty(obj.H.t), lastBin = floor(obj.H.t(end) / obj.decim); end
            k = b > lastBin & [true; diff(b) > 0];
            H = obj.H;
            H.t = [H.t; L.t(k)];  H.err = [H.err; 100 * E(k, :, :)];
            f = ["z" "zh" "v" "T" "Wh" "efc" "sohq" "sohr" "Q"];
            for n = f, H.(n) = [H.(n); L.(n)(k, :)]; end
            H.Qe = [H.Qe; L.Qe(k, :)];
            H.i = [H.i; L.i(k)];  H.mode = [H.mode; L.mode(k)];  H.cycle = [H.cycle; L.cycle(k)];
            % updated table points (weighted count >= 100): median |error| per group
            nm = ["r0" "r1" "tau"]; tb = ["tabR0" "tabR1" "tabTau"]; cn = ["cntR0" "cntR1" "cntTau"];
            te = nan(1, 13, 3); tbias = te;
            for q = 1:3
                Tn = ecmTruthNow(obj.P, L.sohr(end, :), nm(q));
                e = (L.(tb(q)) - Tn) ./ Tn;
                for g = 1:13
                    v = L.(cn(q))(:, :, g) >= 100; eg = e(:, :, g);
                    if any(v(:)), te(1, g, q) = 100 * median(abs(eg(v))); tbias(1, g, q) = 100 * median(eg(v)); end
                end
            end
            H.tabT = [H.tabT; L.t(end)];  H.tabErr = [H.tabErr; te];  H.tabBias = [H.tabBias; tbias];
            obj.H = H;
            % keep only the end state of the chunk (tables, counts, last values)
            last = struct();
            for n = ["tabR0" "tabR1" "tabTau" "cntR0" "cntR1" "cntTau"], last.(n) = L.(n); end
            for n = ["Qe" "sohr" "sohq" "zh" "z" "t"], last.(n) = L.(n)(end, :); end
            obj.last = last;
        end

        function save(obj, file)
            S = struct("P", obj.P, "op", obj.op, "tDone", obj.tDone, "done", obj.done, "conv", obj.conv, ...
                "H", obj.H, "last", obj.last, "decim", obj.decim, "wall", obj.wall, "savedAt", datetime("now"));
            save(file, "S", "-v7");             % compressed
        end
    end

    methods (Static)
        function obj = load(file)
            S = load(file).S;
            obj = EcmEngine(S.P, S.decim);
            for n = ["op" "tDone" "done" "conv" "H" "last" "wall"], obj.(n) = S.(n); end
        end
    end
end

function L = keepAfter(L, t0)
keep = L.t > t0 + 1e-9;
n = numel(L.t);
f = fieldnames(L);
for k = 1:numel(f)
    x = L.(f{k});
    if ~startsWith(f{k}, ["tab" "cnt"]) && size(x, 1) == n, L.(f{k}) = x(keep, :); end
end
end

function y = ifelse(c, a, b)
if c, y = a; else, y = b; end
end
