classdef EcmConvergenceApp < handle
%ECMCONVERGENCEAPP Live view of the adaptive ECM converging (offline, ecmOffline.slx).
%
%   app = EcmConvergenceApp;
%
% Runs ecmOffline in chunks of simulated time (Fast Restart, continuing from the
% operating point of the previous chunk) and updates the plots after each chunk.
% Shows, per parallel group: the error of R0, R1, tau1 and capacity against the true
% values, the time and energy to convergence (ecmConvergence: +/-1 % held 10 min),
% and the SOC x temperature tables (estimate, truth, error, update counts).
% "Save tables" stores the current tables; "Start from saved tables" uses them as the
% starting point of the next run (restart test).

    properties (Access = private)
        fig
        % controls
        hoursEdit; chunkEdit; errMinEdit; errMaxEdit; seedEdit; noiseBox; savedBox
        runBtn; pauseBtn; stopBtn; saveBtn; groupDrop; paramDrop; accelBox
        % header
        clockLbl; whLbl; speedLbl; statusLbl
        % tabs
        convAx; clockTable; tabAx; sigAx
        % state
        conv; P; mdl = "ecmOffline"
        tPlot = zeros(0,1); ePlot = zeros(0,13,4); zPlot = zeros(0,13); zhPlot = zeros(0,13)
        iPlot = zeros(0,1); vPlot = zeros(0,13); TPlot = zeros(0,13); whPlot = zeros(0,13)
        last                      % last chunk's log (tables, counts)
        op                        % operating point to continue from
        tDone = 0
        running = false; paused = false; stopReq = false
        wallStart
    end

    methods
        function app = EcmConvergenceApp()
            app.build();
        end

        function run(app, hours, opts)
            % Scripted run, as pressing Run: app.run(24) or app.run(24, Seed=2, Noise=true)
            arguments
                app
                hours (1,1) double
                opts.Seed (1,1) double = app.seedEdit.Value
                opts.Noise (1,1) logical = app.noiseBox.Value
                opts.FromSaved (1,1) logical = app.savedBox.Value
            end
            app.hoursEdit.Value = hours; app.seedEdit.Value = opts.Seed;
            app.noiseBox.Value = opts.Noise; app.savedBox.Value = opts.FromSaved;
            app.onRun();
        end

        function saveTables(app)
            app.onSave();
        end

        function snapshot(app, file)
            % Saves an image of the app window (exportapp)
            drawnow; exportapp(app.fig, file);
        end

        function selectTab(app, k)
            tg = findobj(app.fig, "Type", "uitabgroup"); tg.SelectedTab = tg.Children(k);
        end

        function delete(app)
            if ~isempty(app.fig) && isvalid(app.fig), delete(app.fig); end
        end
    end

    methods (Access = private)
        %% ---------------------------------------------------------------- UI
        function build(app)
            app.fig = uifigure("Name", "Adaptive ECM convergence", "Position", [60 60 1500 900]);
            app.convAx = gobjects(1, 4); app.tabAx = gobjects(1, 5); app.sigAx = gobjects(1, 4);
            app.fig.CloseRequestFcn = @(~, ~) app.onClose();
            g = uigridlayout(app.fig, [2 2]);
            g.RowHeight = {60, "1x"}; g.ColumnWidth = {270, "1x"};

            % header
            h = uigridlayout(g, [1 4]); h.Layout.Row = 1; h.Layout.Column = [1 2];
            h.ColumnWidth = {"1x", "1x", "1x", "2x"}; h.Padding = [10 5 10 5];
            app.clockLbl = uilabel(h, "Text", "Simulated 0:00:00", "FontSize", 22, "FontWeight", "bold");
            app.whLbl    = uilabel(h, "Text", "Energy (mean per group) 0.0 Wh", "FontSize", 18);
            app.speedLbl = uilabel(h, "Text", "", "FontSize", 16);
            app.statusLbl = uilabel(h, "Text", "Ready", "FontSize", 14);

            % controls
            c = uigridlayout(g, [17 2]); c.Layout.Row = 2; c.Layout.Column = 1;
            c.RowHeight = repmat({28}, 1, 17); c.ColumnWidth = {"1.3x", "1x"};
            row = 0;
            function e = numRow(label, val, lim)
                row = row + 1;
                l = uilabel(c, "Text", label); l.Layout.Row = row; l.Layout.Column = 1;
                e = uieditfield(c, "numeric", "Value", val, "Limits", lim);
                e.Layout.Row = row; e.Layout.Column = 2;
            end
            app.hoursEdit  = numRow("Hours to simulate", 24, [0.1 500]);
            app.chunkEdit  = numRow("Update every (sim min)", 30, [1 240]);
            app.errMinEdit = numRow("Initial error min (%)", 2, [0 50]);
            app.errMaxEdit = numRow("Initial error max (%)", 5, [0 50]);
            app.seedEdit   = numRow("Initial error seed", 1, [1 1e6]);
            row = row + 1;
            app.noiseBox = uicheckbox(c, "Text", "Sensor noise and current offset", "Value", false);
            app.noiseBox.Layout.Row = row; app.noiseBox.Layout.Column = [1 2];
            row = row + 1;
            app.savedBox = uicheckbox(c, "Text", "Start from saved tables", "Value", false);
            app.savedBox.Layout.Row = row; app.savedBox.Layout.Column = [1 2];
            row = row + 1;
            app.accelBox = uicheckbox(c, "Text", "Accelerator mode (faster)", "Value", true);
            app.accelBox.Layout.Row = row; app.accelBox.Layout.Column = [1 2];
            row = row + 1;
            app.runBtn = uibutton(c, "Text", "Run", "ButtonPushedFcn", @(~, ~) app.onRun(), ...
                "BackgroundColor", [0.2 0.6 0.3], "FontColor", "w", "FontWeight", "bold");
            app.runBtn.Layout.Row = row; app.runBtn.Layout.Column = [1 2];
            row = row + 1;
            app.pauseBtn = uibutton(c, "Text", "Pause", "ButtonPushedFcn", @(~, ~) app.onPause(), "Enable", "off");
            app.pauseBtn.Layout.Row = row; app.pauseBtn.Layout.Column = 1;
            app.stopBtn = uibutton(c, "Text", "Stop", "ButtonPushedFcn", @(~, ~) app.onStop(), "Enable", "off");
            app.stopBtn.Layout.Row = row; app.stopBtn.Layout.Column = 2;
            row = row + 1;
            app.saveBtn = uibutton(c, "Text", "Save tables", "ButtonPushedFcn", @(~, ~) app.onSave(), "Enable", "off");
            app.saveBtn.Layout.Row = row; app.saveBtn.Layout.Column = [1 2];
            row = row + 2;
            l = uilabel(c, "Text", "Group"); l.Layout.Row = row; l.Layout.Column = 1;
            app.groupDrop = uidropdown(c, "Items", "Group " + string(1:13), "ItemsData", 1:13, "Value", 1, ...
                "ValueChangedFcn", @(~, ~) app.refresh());
            app.groupDrop.Layout.Row = row; app.groupDrop.Layout.Column = 2;
            row = row + 1;
            l = uilabel(c, "Text", "Table"); l.Layout.Row = row; l.Layout.Column = 1;
            app.paramDrop = uidropdown(c, "Items", ["R0" "R1" "tau1"], "ItemsData", 1:3, "Value", 1, ...
                "ValueChangedFcn", @(~, ~) app.refresh());
            app.paramDrop.Layout.Row = row; app.paramDrop.Layout.Column = 2;
            row = row + 2;
            note = uilabel(c, "Text", ["Converged: error within ±1 % for 10 min" ; ...
                "(time and Wh at the start of that window)"], "FontColor", [0.4 0.4 0.4], "WordWrap", "on");
            note.Layout.Row = [row row+1]; note.Layout.Column = [1 2];

            % tabs
            tg = uitabgroup(g); tg.Layout.Row = 2; tg.Layout.Column = 2;
            t1 = uitab(tg, "Title", "Convergence");
            gl = uigridlayout(t1, [2 2]);
            ttl = ["R0 error (%)" "R1 error (%)" "\tau_1 error (%)" "Capacity error (%)"];
            for k = 1:4
                app.convAx(k) = uiaxes(gl); title(app.convAx(k), ttl(k)); xlabel(app.convAx(k), "Simulated time (h)");
                grid(app.convAx(k), "on"); hold(app.convAx(k), "on");
            end
            t2 = uitab(tg, "Title", "Time and energy to converge");
            gl2 = uigridlayout(t2, [1 1]);
            app.clockTable = uitable(gl2, "FontSize", 13);
            t3 = uitab(tg, "Title", "Lookup tables");
            gl3 = uigridlayout(t3, [2 3]);
            for k = 1:5, app.tabAx(k) = uiaxes(gl3); end
            app.tabAx(5).Layout.Column = [2 3]; app.tabAx(5).Layout.Row = 2;
            app.tabAx(4).Layout.Row = 2; app.tabAx(4).Layout.Column = 1;
            t4 = uitab(tg, "Title", "Signals");
            gl4 = uigridlayout(t4, [2 2]);
            for k = 1:4, app.sigAx(k) = uiaxes(gl4); grid(app.sigAx(k), "on"); end
            app.refresh();
        end

        %% ------------------------------------------------------------ callbacks
        function onRun(app)
            if app.running, return, end
            if app.paused
                app.paused = false; app.runLoop(); return
            end
            app.startRun();
            app.runLoop();
        end

        function onPause(app)
            if app.running, app.paused = true; app.statusLbl.Text = "Pausing after this chunk ..."; end
        end

        function onStop(app)
            app.stopReq = true;
            if ~app.running, app.finish("Stopped"); end
        end

        function onSave(app)
            if isempty(app.last), return, end
            S = ecmSaveTables(app.last);
            app.statusLbl.Text = "Saved tables to " + S.file;
        end

        function onClose(app)
            app.stopReq = true;
            try, set_param(app.mdl, "FastRestart", "off"); catch, end
            delete(app.fig);
        end

        %% ----------------------------------------------------------- simulation
        function startRun(app)
            init = [];
            if app.savedBox.Value
                f = fullfile(fileparts(mfilename("fullpath")), "..", "work", "ecmTables.mat");
                if ~isfile(f), uialert(app.fig, "No saved tables yet (work/ecmTables.mat).", "Saved tables"); return, end
                init = load(f).S;
            end
            app.P = ecmParams(Seed=app.seedEdit.Value, ...
                ErrRange=[app.errMinEdit.Value app.errMaxEdit.Value]/100, ...
                Noise=app.noiseBox.Value, InitTables=init);
            assignin("base", "ECM", app.P);
            load_system(app.mdl);
            set_param(app.mdl, "FastRestart", "off");
            set_param(app.mdl, "SimulationMode", string(ifelse(app.accelBox.Value, "accelerator", "normal")));
            set_param(app.mdl, "SaveFinalState", "on", "SaveOperatingPoint", "on", "FinalStateName", "xFinal", ...
                "LoadInitialState", "off");
            set_param(app.mdl, "FastRestart", "on");
            app.conv = ecmConvergence(0.01, 600);
            app.tPlot = zeros(0,1); app.ePlot = zeros(0,13,4); app.zPlot = zeros(0,13); app.zhPlot = zeros(0,13);
            app.iPlot = zeros(0,1); app.vPlot = zeros(0,13); app.TPlot = zeros(0,13); app.whPlot = zeros(0,13);
            app.op = []; app.tDone = 0; app.last = []; app.stopReq = false; app.paused = false;
            app.wallStart = tic;
        end

        function runLoop(app)
            app.running = true;
            app.runBtn.Enable = "off"; app.pauseBtn.Enable = "on"; app.stopBtn.Enable = "on";
            tEnd = app.hoursEdit.Value * 3600;
            while app.tDone < tEnd - 1e-6 && ~app.stopReq && ~app.paused
                t1 = min(app.tDone + app.chunkEdit.Value * 60, tEnd);
                app.statusLbl.Text = sprintf("Simulating %.2f h to %.2f h ...", app.tDone/3600, t1/3600);
                drawnow;
                in = Simulink.SimulationInput(app.mdl).setModelParameter("StopTime", string(t1));
                if ~isempty(app.op), in = in.setInitialState(app.op); end
                try
                    out = sim(in);
                catch err
                    app.running = false; app.finish("Error: " + err.message); return
                end
                app.op = out.xFinal;
                L = ecmGetLog(out, app.tDone);
                if app.tDone > 0, L = dropFirst(L); end
                app.ingest(L);
                app.tDone = t1;
                app.refresh();
                drawnow;
            end
            app.running = false;
            if app.paused
                app.statusLbl.Text = "Paused (Run to continue)";
                app.runBtn.Enable = "on"; app.runBtn.Text = "Continue";
            else
                app.finish(ifelse(app.stopReq, "Stopped", "Finished"));
            end
        end

        function finish(app, msg)
            app.running = false; app.paused = false;
            app.runBtn.Enable = "on"; app.runBtn.Text = "Run";
            app.pauseBtn.Enable = "off"; app.stopBtn.Enable = "off";
            app.saveBtn.Enable = matlab.lang.OnOffSwitchState(~isempty(app.last));
            try, set_param(app.mdl, "FastRestart", "off"); catch, end
            app.statusLbl.Text = string(msg);
        end

        function ingest(app, L)
            E = cat(3, (L.r0e - L.r0) ./ L.r0, (L.r1e - L.r1) ./ L.r1, (L.taue - L.tau) ./ L.tau, ...
                (L.Qe - app.P.plant.Q) ./ app.P.plant.Q);
            app.conv.add(L.t, E, L.Wh);
            k = mod(round(L.t), 10) == 0;          % keep every 10 s for plotting
            app.tPlot = [app.tPlot; L.t(k)];
            app.ePlot = [app.ePlot; 100 * E(k, :, :)];
            app.zPlot = [app.zPlot; L.z(k, :)]; app.zhPlot = [app.zhPlot; L.zh(k, :)];
            app.iPlot = [app.iPlot; L.i(k)]; app.vPlot = [app.vPlot; L.v(k, :)];
            app.TPlot = [app.TPlot; L.T(k, :)]; app.whPlot = [app.whPlot; L.Wh(k, :)];
            app.last = L;
            app.saveBtn.Enable = "on";
        end

        %% -------------------------------------------------------------- display
        function refresh(app)
            g = app.groupDrop.Value;
            th = app.tPlot / 3600;
            % header
            if ~isempty(app.conv)
                s = app.conv.tNow;
                app.clockLbl.Text = sprintf("Simulated %d:%02d:%02d", floor(s/3600), floor(mod(s,3600)/60), floor(mod(s,60)));
                app.whLbl.Text = sprintf("Energy per group %.0f Wh (group %d %.0f Wh)", mean(app.conv.whNow), g, app.conv.whNow(g));
                if ~isempty(app.wallStart)
                    w = toc(app.wallStart);
                    app.speedLbl.Text = sprintf("%.0f x real time (%.0f s wall)", s / max(w, eps), w);
                end
            end
            % convergence plots
            for p = 1:4
                ax = app.convAx(p); cla(ax);
                if ~isempty(th)
                    plot(ax, th, app.ePlot(:, :, p), "Color", [0.6 0.6 0.6 0.5], "LineWidth", 0.5);
                    plot(ax, th, app.ePlot(:, g, p), "Color", [0.85 0.33 0.1], "LineWidth", 1.8);
                    yline(ax, [-1 1], "--", "Color", [0.1 0.5 0.1]);
                    ct = app.conv.convT(g, p);
                    if ~isnan(ct), xline(ax, ct/3600, "-", sprintf("G%d converged", g), "Color", [0.1 0.5 0.1]); end
                    ylim(ax, [-8 8]);
                end
            end
            % clock table
            if ~isempty(app.conv)
                app.clockTable.Data = app.clockData();
            end
            % lookup tables
            app.drawTables(g, app.paramDrop.Value);
            % signals
            for k = 1:4, cla(app.sigAx(k)); end
            if ~isempty(th)
                plot(app.sigAx(1), th, 100*app.zPlot(:, g), th, 100*app.zhPlot(:, g), "--");
                title(app.sigAx(1), sprintf("Group %d SOC (%%): true, estimated", g)); legend(app.sigAx(1), ["true" "estimated"]);
                plot(app.sigAx(2), th, app.iPlot); title(app.sigAx(2), "Pack current (A), discharge +");
                plot(app.sigAx(3), th, app.vPlot(:, g)); title(app.sigAx(3), sprintf("Group %d voltage (V)", g));
                plot(app.sigAx(4), th, app.TPlot); title(app.sigAx(4), "Group temperatures (°C)");
                for k = 1:4, xlabel(app.sigAx(k), "Simulated time (h)"); end
            end
        end

        function C = clockData(app)
            cv = app.conv; nm = ["R0" "R1" "tau1" "Q"];
            C = table((1:13)', 'VariableNames', "Group");
            for p = 1:4
                tt = strings(13, 1); ww = strings(13, 1);
                for g = 1:13
                    if ~isnan(cv.convT(g, p))
                        tt(g) = hm(cv.convT(g, p)); ww(g) = sprintf("%.0f", cv.convWh(g, p));
                        if ~isnan(cv.leftT(g, p)), tt(g) = tt(g) + " (left band " + hm(cv.leftT(g, p)) + ")"; end
                    else
                        tt(g) = "not yet (" + hm(cv.tNow) + ")"; ww(g) = sprintf("> %.0f", cv.whNow(g));
                    end
                end
                C.(nm(p) + " time") = tt; C.(nm(p) + " Wh") = ww;
            end
        end

        function drawTables(app, g, p)
            for k = 1:5, cla(app.tabAx(k)); colorbar(app.tabAx(k), "off"); end
            if isempty(app.P), return, end
            es = app.P.est; nm = ["r0" "r1" "tau"]; lbl = ["R0 (mΩ)" "R1 (mΩ)" "\tau_1 (s)"]; sc = [1e3 1e3 1];
            tr = app.P.truth.(nm(p))(:, :, g) * sc(p);
            if isempty(app.last)
                est = app.P.est.init.(nm(p))(:, :, g) * sc(p); cnt = app.P.est.init.count(:, :, g, p);
            else
                f = ["tabR0" "tabR1" "tabTau"]; fc = ["cntR0" "cntR1" "cntTau"];
                est = app.last.(f(p))(:, :, g) * sc(p); cnt = app.last.(fc(p))(:, :, g);
            end
            err = 100 * (est - tr) ./ tr;
            x = es.tBpC; y = 100 * es.socBp;
            show(app.tabAx(1), x, y, est, "Estimate, group " + g + ": " + lbl(p), []);
            show(app.tabAx(2), x, y, tr, "True: " + lbl(p) + " (no temperature dependence yet)", [min(tr(:)) max(tr(:))]);
            show(app.tabAx(3), x, y, err, "Error (%)", [-5 5]);
            colormap(app.tabAx(3), redblue());
            show(app.tabAx(4), x, y, log10(1 + cnt), "Updates, log_{10}(1 + weighted count)", []);
            % per-SOC view at the temperature columns that have updates
            ax = app.tabAx(5); hold(ax, "on"); grid(ax, "on");
            plot(ax, y, tr(:, 1), "k-", "LineWidth", 2, "DisplayName", "true");
            used = find(sum(cnt, 1) > 0);
            for j = used
                plot(ax, y, est(:, j), "o-", "DisplayName", sprintf("estimate, %g °C column", x(j)));
            end
            if isempty(used), plot(ax, y, est(:, 1), "o--", "DisplayName", "estimate (no updates yet)"); end
            xlabel(ax, "SOC (%)"); ylabel(ax, lbl(p)); legend(ax, "Location", "best"); hold(ax, "off");
        end
    end
end

%% helpers
function show(ax, x, y, Z, ttl, cl)
imagesc(ax, x, y, Z); axis(ax, "xy"); axis(ax, "tight");
xlabel(ax, "Temperature (°C)"); ylabel(ax, "SOC (%)"); title(ax, ttl);
colorbar(ax);
if ~isempty(cl) && cl(2) > cl(1), clim(ax, cl); end
end

function c = redblue()
n = 64; a = linspace(0, 1, n/2)';
c = [[a a ones(n/2,1)]; [ones(n/2,1) flipud(a) flipud(a)]];
end

function s = hm(t)
s = sprintf("%d:%02d", floor(t/3600), floor(mod(t, 3600)/60));
end

function L = dropFirst(L)
f = fieldnames(L);
for k = 1:numel(f)
    x = L.(f{k});
    if ~startsWith(f{k}, ["tab" "cnt"]) && size(x, 1) > 1, L.(f{k}) = x(2:end, :); end
end
end

function y = ifelse(c, a, b)
if c, y = a; else, y = b; end
end
