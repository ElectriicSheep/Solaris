classdef EcmConvergenceApp < handle
%ECMCONVERGENCEAPP Adaptive ECM test bench (offline, ecmOffline.slx).
%
%   app = EcmConvergenceApp;
%
% Live: runs ecmOffline in chunks (EcmEngine, Fast Restart, continuing from the
% operating point of the previous chunk) and redraws after each chunk.
% Replay: "Open results" loads a saved run (ecmBatch or a previous live run); the
% "View up to" slider and Play step through it.
%
% Tabs: Convergence (worst |error| in the last 10 min, per parameter), Time and energy
% to converge, Lookup tables (SOC x temperature, estimate / truth / error / counts),
% Signals, Pack, Ageing, Initial conditions (per group SOC, SOHr, SOHq, temperature,
% cycles). All plant values are SYNTHETIC PLACEHOLDERS.

    properties (Access = private)
        fig
        % controls
        hoursEdit; cyclesEdit; chunkEdit; profileDrop; methodDrop
        errMinEdit; errMaxEdit; seedEdit; shapeDrop; baseDrop
        spreadBox; noiseBox; tempBox; degBox; savedBox; continueBox; accelBox; trendBox; ageEdit
        runBtn; pauseBtn; stopBtn; saveBtn; openBtn; groupDrop; paramDrop
        % header
        clockLbl; whLbl; speedLbl; statusLbl; viewSlider; playBtn
        % tabs
        tabGroup; convAx; clockTable; tabAx; sigAx; packAx; packTable; ageAx; icTable; ambEdit
        % state
        E                       % EcmEngine (live or loaded)
        P0                      % default parameters (degradation constants for the IC tab)
        running = false; paused = false; stopReq = false; playing = false
        tView = inf             % s, display up to this time
        lastRunFile
    end

    methods
        function app = EcmConvergenceApp()
            app.P0 = ecmParams();
            app.lastRunFile = fullfile(fileparts(fileparts(mfilename("fullpath"))), "work", "ecmLastRun.mat");
            app.build();
        end

        function run(app, hours, opts)
            % Scripted run, as pressing Run: app.run(24) or app.run(0, Cycles=3, Profile="ideal")
            arguments
                app
                hours (1,1) double
                opts.Cycles (1,1) double = 0
                opts.Seed (1,1) double = app.seedEdit.Value
                opts.Noise (1,1) logical = app.noiseBox.Value
                opts.FromSaved (1,1) logical = app.savedBox.Value
                opts.Shape (1,1) string = app.shapeDrop.Value
                opts.Spread (1,1) logical = app.spreadBox.Value
                opts.Profile (1,1) string = app.profileDrop.Value
                opts.Continue (1,1) logical = false
            end
            app.hoursEdit.Value = max(hours, 0.1); app.cyclesEdit.Value = opts.Cycles;
            app.seedEdit.Value = opts.Seed; app.noiseBox.Value = opts.Noise; app.savedBox.Value = opts.FromSaved;
            app.shapeDrop.Value = opts.Shape; app.spreadBox.Value = opts.Spread;
            app.profileDrop.Value = opts.Profile; app.continueBox.Value = opts.Continue;
            app.onRun();
        end

        function openResults(app, file)
            app.loadResults(file);
        end

        function snapshot(app, file)
            drawnow; exportapp(app.fig, file);
        end

        function selectTab(app, k)
            app.tabGroup.SelectedTab = app.tabGroup.Children(k);
            app.refresh();
        end

        function delete(app)
            if ~isempty(app.fig) && isvalid(app.fig), delete(app.fig); end
        end
    end

    methods (Access = private)
        %% ---------------------------------------------------------------- UI
        function build(app)
            app.fig = uifigure("Name", "Adaptive ECM convergence", "Position", [40 40 1560 940]);
            app.convAx = gobjects(1, 4); app.tabAx = gobjects(1, 5); app.sigAx = gobjects(1, 4);
            app.packAx = gobjects(1, 5); app.ageAx = gobjects(1, 4);
            app.fig.CloseRequestFcn = @(~, ~) app.onClose();
            g = uigridlayout(app.fig, [2 2]);
            g.RowHeight = {78, "1x"}; g.ColumnWidth = {300, "1x"};

            % header: clock, energy, speed, status; view slider and play for replay
            h = uigridlayout(g, [2 4]); h.Layout.Row = 1; h.Layout.Column = [1 2];
            h.ColumnWidth = {"1x", "1.6x", "0.9x", "1.6x"}; h.RowHeight = {32, 28}; h.Padding = [10 2 10 2];
            app.clockLbl = uilabel(h, "Text", "Cycle 0   0:00:00", "FontSize", 22, "FontWeight", "bold");
            app.whLbl    = uilabel(h, "Text", "", "FontSize", 14);
            app.speedLbl = uilabel(h, "Text", "", "FontSize", 14);
            app.statusLbl = uilabel(h, "Text", "Ready", "FontSize", 13);
            l = uilabel(h, "Text", "View up to (h):", "HorizontalAlignment", "right"); l.Layout.Row = 2; l.Layout.Column = 1;
            app.viewSlider = uislider(h, "Limits", [0 1], "Value", 1, "MajorTicks", [], "MinorTicks", [], ...
                "ValueChangedFcn", @(s, ~) app.onView(s.Value));
            app.viewSlider.Layout.Row = 2; app.viewSlider.Layout.Column = [2 3];
            app.playBtn = uibutton(h, "Text", "Play", "ButtonPushedFcn", @(~, ~) app.onPlay());
            app.playBtn.Layout.Row = 2; app.playBtn.Layout.Column = 4;

            % controls (scrollable)
            pnl = uipanel(g, "BorderType", "none", "Scrollable", "on"); pnl.Layout.Row = 2; pnl.Layout.Column = 1;
            nRows = 35;
            c = uigridlayout(pnl, [nRows 2]); c.RowHeight = repmat({26}, 1, nRows); c.ColumnWidth = {"1.25x", "1x"};
            c.Scrollable = "on";
            row = 0;
            function lab(txt)
                row = row + 1;
                q = uilabel(c, "Text", txt, "FontWeight", "bold"); q.Layout.Row = row; q.Layout.Column = [1 2];
            end
            function e = numRow(label, val, lim)
                row = row + 1;
                q = uilabel(c, "Text", label); q.Layout.Row = row; q.Layout.Column = 1;
                e = uieditfield(c, "numeric", "Value", val, "Limits", lim);
                e.Layout.Row = row; e.Layout.Column = 2;
            end
            function d = dropRow(label, items, data, val)
                row = row + 1;
                q = uilabel(c, "Text", label); q.Layout.Row = row; q.Layout.Column = 1;
                d = uidropdown(c, "Items", items, "ItemsData", data, "Value", val);
                d.Layout.Row = row; d.Layout.Column = 2;
            end
            function b = boxRow(label, val)
                row = row + 1;
                b = uicheckbox(c, "Text", label, "Value", val); b.Layout.Row = row; b.Layout.Column = [1 2];
            end
            lab("Run");
            app.hoursEdit  = numRow("Hours to simulate", 24, [0.1 1e5]);
            app.cyclesEdit = numRow("or cycles (0 = use hours)", 0, [0 1e4]);
            app.chunkEdit  = numRow("Update every (sim min)", 30, [1 1440]);
            app.profileDrop = dropRow("Load profile", ["CYCLE A (marine)" "Ideal excitation"], ["cycleA" "ideal"], "cycleA");
            app.methodDrop = dropRow("Estimation method", ["FFRLS + EKF" "Dual EKF"], ["ffrls" "dekf"], "ffrls");
            lab("Estimator start");
            app.errMinEdit = numRow("Initial error min (%)", 2, [0 50]);
            app.errMaxEdit = numRow("Initial error max (%)", 5, [0 50]);
            app.seedEdit   = numRow("Initial error seed", 1, [1 1e6]);
            app.shapeDrop  = dropRow("Error shape", ["one per group" "smooth over table" "independent per point"], ...
                ["group" "smooth" "node"], "smooth");
            app.baseDrop   = dropRow("Errors relative to", ["true values at start" "new-cell values"], ["current" "new"], "current");
            app.spreadBox  = boxRow("Spread learning to unvisited points", true);
            app.savedBox   = boxRow("Start from saved tables", false);
            app.trendBox   = boxRow("Capacity trend (derivative)", false);
            lab("Plant (placeholders)");
            app.tempBox  = boxRow("Temperature dependence", true);
            app.degBox   = boxRow("Degradation", true);
            app.noiseBox = boxRow("Sensor noise and current offset", false);
            app.ageEdit  = numRow("Ageing speed-up (x)", 1, [0.1 1000]);
            lab("Run control");
            app.continueBox = boxRow("Continue from the end of the last run", false);
            app.accelBox = boxRow("Accelerator mode (faster)", true);
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
            app.saveBtn.Layout.Row = row; app.saveBtn.Layout.Column = 1;
            app.openBtn = uibutton(c, "Text", "Open results...", "ButtonPushedFcn", @(~, ~) app.onOpen());
            app.openBtn.Layout.Row = row; app.openBtn.Layout.Column = 2;
            lab("Display");
            app.groupDrop = dropRow("Group", "Group " + string(1:13), 1:13, 1);
            app.groupDrop.ValueChangedFcn = @(~, ~) app.refresh();
            app.paramDrop = dropRow("Table", ["R0" "R1" "tau1"], 1:3, 1);
            app.paramDrop.ValueChangedFcn = @(~, ~) app.refresh();
            row = row + 1;
            note = uilabel(c, "Text", "Converged: within ±1 % for 10 min (time, Wh at the start of that window)", ...
                "FontColor", [0.55 0.55 0.55], "WordWrap", "on");
            note.Layout.Row = [row row+1]; note.Layout.Column = [1 2];

            % tabs
            app.tabGroup = uitabgroup(g, "SelectionChangedFcn", @(~, ~) app.refresh());
            tg = app.tabGroup; tg.Layout.Row = 2; tg.Layout.Column = 2;
            gl = uigridlayout(uitab(tg, "Title", "Convergence"), [2 2]);
            for k = 1:4, app.convAx(k) = uiaxes(gl); end
            gl = uigridlayout(uitab(tg, "Title", "Time and energy to converge"), [1 1]);
            app.clockTable = uitable(gl, "FontSize", 13);
            gl = uigridlayout(uitab(tg, "Title", "Lookup tables"), [2 3]);
            for k = 1:5, app.tabAx(k) = uiaxes(gl); end
            app.tabAx(4).Layout.Row = 2; app.tabAx(4).Layout.Column = 1;
            app.tabAx(5).Layout.Row = 2; app.tabAx(5).Layout.Column = [2 3];
            gl = uigridlayout(uitab(tg, "Title", "Signals"), [2 2]);
            for k = 1:4, app.sigAx(k) = uiaxes(gl); end
            gl = uigridlayout(uitab(tg, "Title", "Pack"), [2 3]);
            for k = 1:5, app.packAx(k) = uiaxes(gl); end
            app.packTable = uitable(gl, "FontSize", 12); app.packTable.Layout.Row = 2; app.packTable.Layout.Column = 3;
            gl = uigridlayout(uitab(tg, "Title", "Ageing"), [2 2]);
            for k = 1:4, app.ageAx(k) = uiaxes(gl); end
            app.buildIcTab(uitab(tg, "Title", "Initial conditions"));
            app.refresh();
        end

        function buildIcTab(app, t)
            gl = uigridlayout(t, [3 4]); gl.RowHeight = {30, "1x", 60}; gl.ColumnWidth = {"1x", "1x", "1x", "1x"};
            l = uilabel(gl, "Text", "Ambient temperature (°C)"); l.Layout.Row = 1; l.Layout.Column = 1;
            app.ambEdit = uieditfield(gl, "numeric", "Value", 15, "Limits", [-20 60]);
            app.ambEdit.Layout.Row = 1; app.ambEdit.Layout.Column = 2;
            b = uibutton(gl, "Text", "Copy group 1 to all groups", "ButtonPushedFcn", @(~, ~) app.icCopy());
            b.Layout.Row = 1; b.Layout.Column = 3;
            b = uibutton(gl, "Text", "Reset to new cells", "ButtonPushedFcn", @(~, ~) app.icReset());
            b.Layout.Row = 1; b.Layout.Column = 4;
            app.icTable = uitable(gl, "ColumnEditable", [false true true true true true], "FontSize", 13, ...
                "CellEditCallback", @(s, e) app.icEdited(e));
            app.icTable.Layout.Row = 2; app.icTable.Layout.Column = [1 4];
            note = uilabel(gl, "WordWrap", "on", "FontColor", [0.6 0.6 0.6], "Text", ...
                "Cycles are equivalent full cycles (charge throughput / 2 Q_new). Editing a group's cycles sets its " + ...
                "SOHq and SOHr from the degradation model (cycling at that group's temperature, no calendar ageing); " + ...
                "SOHq and SOHr can then be overridden. SOHq = Q/Q_new, SOHr = R_new/R. End of life SOHq = 70 %. " + ...
                "PLACEHOLDER model. Not used with 'Continue from the end of the last run'.");
            note.Layout.Row = 3; note.Layout.Column = [1 4];
            app.icReset();
        end

        function icReset(app)
            n = 13;
            app.icTable.Data = table((1:n)', 95 * ones(n, 1), 100 * ones(n, 1), 100 * ones(n, 1), ...
                15 * ones(n, 1), zeros(n, 1), 'VariableNames', ["Group" "SOC (%)" "SOHr (%)" "SOHq (%)" "Temperature (°C)" "Cycles (EFC)"]);
        end

        function icCopy(app)
            D = app.icTable.Data;
            for k = 2:width(D), D{:, k} = D{1, k} * ones(height(D), 1); end
            app.icTable.Data = D;
        end

        function icEdited(app, e)
            if e.Indices(2) ~= 6, return, end
            D = app.icTable.Data; r = e.Indices(1);
            [sq, sr] = ecmSohFromCycles(app.P0, D{r, 6}, D{r, 5});
            D{r, 4} = 100 * sq; D{r, 3} = 100 * sr;
            app.icTable.Data = D;
        end

        function ic = icStruct(app)
            D = app.icTable.Data;
            ic = struct("soc0", D{:, 2}' / 100, "sohr0", D{:, 3}' / 100, "sohq0", D{:, 4}' / 100, ...
                "T0C", D{:, 5}', "cyc0", D{:, 6}', "tAmbC", app.ambEdit.Value);
        end

        %% ------------------------------------------------------------ callbacks
        function onRun(app)
            if app.running, return, end
            if app.paused
                app.paused = false; app.runLoop(); return
            end
            if ~app.startRun(), return, end
            app.runLoop();
        end

        function onPause(app)
            if app.running, app.paused = true; app.statusLbl.Text = "Pausing after this chunk ..."; end
        end

        function onStop(app)
            app.stopReq = true; app.playing = false;
            if ~app.running, app.finish("Stopped"); end
        end

        function onSave(app)
            if isempty(app.E) || isempty(app.E.last), return, end
            L = app.E.last;
            S.r0 = L.tabR0; S.r1 = L.tabR1; S.tau = L.tabTau;
            S.count = cat(4, L.cntR0, L.cntR1, L.cntTau); S.Q = L.Qe;
            S.savedAt = datetime("now"); S.simTime_s = app.E.tDone;
            f = fullfile(fileparts(app.lastRunFile), "ecmTables.mat");
            save(f, "S");
            app.statusLbl.Text = "Saved tables to " + f;
        end

        function onOpen(app)
            [f, p] = uigetfile("*.mat", "Open a saved run (ecmBatch or ecmLastRun.mat)", fileparts(app.lastRunFile));
            if isequal(f, 0), return, end
            app.loadResults(fullfile(p, f));
        end

        function loadResults(app, file)
            app.E = EcmEngine.load(file);
            app.tView = inf;
            app.statusLbl.Text = "Loaded " + file + " (replay: use View up to / Play)";
            app.saveBtn.Enable = "on";
            app.refresh();
        end

        function onView(app, v)
            app.tView = v * 3600;
            app.refresh();
        end

        function onPlay(app)
            if isempty(app.E) || isempty(app.E.H.t) || app.running, return, end
            if app.playing, app.playing = false; app.playBtn.Text = "Play"; return, end
            app.playing = true; app.playBtn.Text = "Pause replay";
            tEnd = app.E.H.t(end); t = min(app.tView, tEnd); if t >= tEnd, t = 0; end
            step = tEnd / 200;
            while app.playing && t < tEnd
                t = min(t + step, tEnd); app.tView = t; app.viewSlider.Value = t / 3600;
                app.refresh(); drawnow; pause(0.03);
            end
            app.playing = false; app.playBtn.Text = "Play";
        end

        function onClose(app)
            app.stopReq = true; app.playing = false;
            if ~isempty(app.E), app.E.stopFastRestart(); end
            delete(app.fig);
        end

        %% ----------------------------------------------------------- simulation
        function ok = startRun(app)
            ok = false;
            if app.continueBox.Value
                if ~isempty(app.E) && ~isempty(app.E.op)
                    % continue the engine in memory
                elseif isfile(app.lastRunFile)
                    app.E = EcmEngine.load(app.lastRunFile);
                else
                    uialert(app.fig, "No previous run to continue.", "Continue"); return
                end
                app.E.done = false;
                app.statusLbl.Text = "Continuing the last run (its own settings; panel settings other than the duration are ignored)";
            else
                init = [];
                if app.savedBox.Value
                    f = fullfile(fileparts(app.lastRunFile), "ecmTables.mat");
                    if ~isfile(f), uialert(app.fig, "No saved tables yet (work/ecmTables.mat).", "Saved tables"); return, end
                    init = load(f).S;
                end
                P = ecmParams(Seed=app.seedEdit.Value, ErrRange=[app.errMinEdit.Value app.errMaxEdit.Value]/100, ...
                    Noise=app.noiseBox.Value, InitTables=init, ErrShape=app.shapeDrop.Value, Spread=app.spreadBox.Value, ...
                    Profile=app.profileDrop.Value, IC=app.icStruct(), TempDep=app.tempBox.Value, ...
                    Degradation=app.degBox.Value, ErrBase=app.baseDrop.Value, Method=app.methodDrop.Value, ...
                    TrendQ=app.trendBox.Value, AgeingScale=app.ageEdit.Value);
                app.E = EcmEngine(P, 10);
            end
            app.E.start(Accelerator=app.accelBox.Value);
            app.stopReq = false; app.paused = false; app.tView = inf;
            ok = true;
        end

        function runLoop(app)
            app.running = true;
            app.runBtn.Enable = "off"; app.pauseBtn.Enable = "on"; app.stopBtn.Enable = "on"; app.openBtn.Enable = "off";
            E = app.E;
            t0 = E.tDone;
            if app.cyclesEdit.Value > 0
                c0 = 0; if ~isempty(E.H.cycle), c0 = E.H.cycle(end); end
                E.P.load.nCycles = c0 + app.cyclesEdit.Value;
                tEnd = inf;
            else
                E.P.load.nCycles = inf;
                tEnd = t0 + app.hoursEdit.Value * 3600;
            end
            while E.tDone < tEnd - 1e-6 && ~E.done && ~app.stopReq && ~app.paused
                t1 = min(E.tDone + app.chunkEdit.Value * 60, tEnd);
                app.statusLbl.Text = sprintf("Simulating %.2f h to %.2f h ...", E.tDone/3600, t1/3600);
                drawnow;
                try
                    E.advance(t1);
                catch err
                    app.running = false; app.finish("Error: " + err.message); return
                end
                app.refresh();
                drawnow;
            end
            app.running = false;
            try, E.save(app.lastRunFile); catch, end
            if app.paused
                app.statusLbl.Text = "Paused (Run to continue)";
                app.runBtn.Enable = "on"; app.runBtn.Text = "Continue";
            else
                app.finish(ifelse(app.stopReq, "Stopped", "Finished") + " (saved for 'Continue')");
            end
        end

        function finish(app, msg)
            app.running = false; app.paused = false;
            app.runBtn.Enable = "on"; app.runBtn.Text = "Run"; app.openBtn.Enable = "on";
            app.pauseBtn.Enable = "off"; app.stopBtn.Enable = "off";
            app.saveBtn.Enable = matlab.lang.OnOffSwitchState(~isempty(app.E) && ~isempty(app.E.last));
            if ~isempty(app.E), app.E.stopFastRestart(); end
            app.statusLbl.Text = string(msg);
        end

        %% -------------------------------------------------------------- display
        function [H, k] = view(app)
            H = []; k = [];
            if isempty(app.E) || isempty(app.E.H.t), return, end
            H = app.E.H;
            k = H.t <= app.tView;
            if ~any(k), k(1) = true; end
        end

        function refresh(app)
            [H, k] = app.view();
            g = app.groupDrop.Value;
            if isempty(H)
                app.clearAll(); return
            end
            th = H.t(k) / 3600; n = find(k, 1, "last");
            % header
            app.viewSlider.Limits = [0 max(H.t(end) / 3600, 1e-3)];
            if ~app.playing, app.viewSlider.Value = min(th(end), app.viewSlider.Limits(2)); end
            s = H.t(n);
            app.clockLbl.Text = sprintf("Cycle %d   %d:%02d:%02d", H.cycle(n), floor(s/3600), floor(mod(s,3600)/60), floor(mod(s,60)));
            app.whLbl.Text = sprintf("Energy per group %.0f Wh   EFC %.1f   SOHq min %.1f %%", ...
                mean(H.Wh(n, :)), mean(H.efc(n, :)), 100 * min(H.sohq(n, :)));
            if app.E.wall > 0
                app.speedLbl.Text = sprintf("%.0f x real time (%.0f s wall)", app.E.tDone / app.E.wall, app.E.wall);
            end
            switch app.tabGroup.SelectedTab.Title
                case "Convergence"
                    for p = 1:4, app.drawConv(p, g, H, k, th); end
                case "Time and energy to converge"
                    app.clockTable.Data = app.clockData(s);
                case "Lookup tables"
                    app.drawTables(g, app.paramDrop.Value);
                case "Signals"
                    app.drawSignals(g, H, k, th);
                case "Pack"
                    app.drawPack(H, k, th);
                case "Ageing"
                    app.drawAgeing(g, H, k, th);
            end
        end

        function clearAll(app)
            for ax = [app.convAx app.tabAx app.sigAx app.packAx app.ageAx], cla(ax); end
        end

        function drawConv(app, p, g, H, k, th)
            % Plotted quantity: the largest |error| over the last 10 min of simulated time
            % (the convergence rule): below the 1 % line = within the band for 10 min.
            ax = app.convAx(p);
            delete(ax.Children); legend(ax, "off"); hold(ax, "on");
            ttl = ["R0" "R1" "\tau_1" "Capacity"];
            set(ax, "YScale", "log"); ylim(ax, [0.01 30]); grid(ax, "on"); ax.YMinorGrid = "off";
            yticks(ax, [0.01 0.1 1 10]); yticklabels(ax, ["0.01" "0.1" "1" "10"]);
            xlabel(ax, "Simulated time (h)"); ylabel(ax, "worst |error| in last 10 min (%)");
            title(ax, ttl(p));
            xlim(ax, [0 max(th(end), 0.1)]);
            shadePhases(ax, th, H.mode(k), p == 1);
            cycleMarks(ax, th, H.cycle(k), [0.01 30]);
            dt = max(median(diff(H.t)), 1);
            nw = max(round(600 / dt), 1);
            Eh = movmax(max(abs(H.err(k, :, p)), 0.01), [nw-1 0], 1);
            lo = min(Eh, [], 2); hi = max(Eh, [], 2); md = median(Eh, 2);
            fill(ax, [th; flipud(th)], [lo; flipud(hi)], [0 0.45 0.74], "FaceAlpha", 0.20, ...
                "EdgeColor", "none", "DisplayName", "13 groups (range)");
            plot(ax, th, md, "Color", [0.3 0.6 0.95], "LineWidth", 1.3, "DisplayName", "median group");
            plot(ax, th, Eh(:, g), "Color", [0.95 0.45 0.1], "LineWidth", 1.8, "DisplayName", "group " + g);
            if p <= 3 && ~isempty(H.tabT)
                kt = H.tabT <= H.t(find(k, 1, "last"));
                plot(ax, H.tabT(kt)/3600, median(H.tabErr(kt, :, p), 2, "omitnan"), "s-", "Color", [0.5 0.75 0.2], ...
                    "MarkerFaceColor", [0.5 0.75 0.2], "MarkerSize", 3.5, "LineWidth", 1, ...
                    "DisplayName", "table points updated so far (median)");
            end
            plot(ax, [0 th(end)], [1 1], "-", "Color", [0.2 0.75 0.3], "LineWidth", 1.5, "DisplayName", "1 % band");
            cv = app.E.conv; tNow = H.t(find(k, 1, "last"));
            ct = cv.convT(g, p); lt = cv.leftT(g, p);
            if ~isnan(ct) && ct <= tNow
                plot(ax, ct/3600, 1, "o", "MarkerSize", 8, "LineWidth", 1.5, "Color", [0.95 0.45 0.1], "HandleVisibility", "off");
                st = sprintf("group %d: in band from %s (%.0f Wh)", g, hm(ct), cv.convWh(g, p));
                if ~isnan(lt) && lt <= tNow, st = st + sprintf(", left %s", hm(lt)); end
            else
                st = sprintf("group %d: not yet within 1 %% for 10 min", g);
            end
            nConv = sum(cv.convT(:, p) <= tNow); nLeft = sum(cv.leftT(:, p) <= tNow);
            subtitle(ax, st + sprintf("  |  %d/13 groups reached the band, %d later left it", nConv, nLeft), "FontSize", 9);
            if p == 1, legend(ax, "Location", "southwest", "FontSize", 8, "NumColumns", 2); end
            hold(ax, "off");
        end

        function C = clockData(app, tNow)
            cv = app.E.conv; nm = ["R0" "R1" "tau1" "Q"];
            C = table((1:13)', 'VariableNames', "Group");
            Wh = app.E.H.Wh(find(app.E.H.t <= tNow, 1, "last"), :);
            for p = 1:4
                tt = strings(13, 1); ww = strings(13, 1);
                for g = 1:13
                    if ~isnan(cv.convT(g, p)) && cv.convT(g, p) <= tNow
                        tt(g) = hm(cv.convT(g, p)); ww(g) = sprintf("%.0f", cv.convWh(g, p));
                        if ~isnan(cv.leftT(g, p)) && cv.leftT(g, p) <= tNow, tt(g) = tt(g) + " (left " + hm(cv.leftT(g, p)) + ")"; end
                    else
                        tt(g) = "not yet (" + hm(tNow) + ")"; ww(g) = sprintf("> %.0f", Wh(g));
                    end
                end
                C.(nm(p) + " time") = tt; C.(nm(p) + " Wh") = ww;
            end
        end

        function drawTables(app, g, p)
            for k = 1:5, cla(app.tabAx(k)); colorbar(app.tabAx(k), "off"); legend(app.tabAx(k), "off"); end
            P = app.E.P; es = P.est; nm = ["r0" "r1" "tau"]; lbl = ["R0 (mΩ)" "R1 (mΩ)" "\tau_1 (s)"]; sc = [1e3 1e3 1];
            L = app.E.last;
            if isempty(L)
                sohr = P.ic.sohr0; est = es.init.(nm(p))(:, :, g) * sc(p); cnt = es.init.count(:, :, g, p);
            else
                f = ["tabR0" "tabR1" "tabTau"]; fc = ["cntR0" "cntR1" "cntTau"];
                sohr = L.sohr; est = L.(f(p))(:, :, g) * sc(p); cnt = L.(fc(p))(:, :, g);
            end
            tr = ecmTruthNow(P, sohr, nm(p)); tr = tr(:, :, g) * sc(p);
            err = 100 * (est - tr) ./ tr;
            x = es.tBpC; y = 100 * es.socBp;
            show(app.tabAx(1), x, y, est, "Estimate, group " + g + ": " + lbl(p) + " (end of the run)", []);
            show(app.tabAx(2), x, y, tr, "True now: " + lbl(p), [min(tr(:)) max(tr(:))]);
            show(app.tabAx(3), x, y, err, "Error (%)", [-5 5]);
            colormap(app.tabAx(3), redblue());
            show(app.tabAx(4), x, y, log10(1 + cnt), "Updates, log_{10}(1 + weighted count)", []);
            ax = app.tabAx(5); hold(ax, "on"); grid(ax, "on");
            used = find(sum(cnt, 1) > 0);
            if isempty(used), used = 2; end
            cols = lines(numel(used));
            for jj = 1:numel(used)
                j = used(jj);
                plot(ax, y, tr(:, j), "-", "Color", [1 1 1], "LineWidth", 2, "DisplayName", sprintf("true, %g °C", x(j)));
                plot(ax, y, est(:, j), "o-", "Color", cols(jj, :), "LineWidth", 1.2, "DisplayName", sprintf("estimate, %g °C", x(j)));
            end
            xlabel(ax, "SOC (%)"); ylabel(ax, lbl(p)); legend(ax, "Location", "best"); hold(ax, "off");
        end

        function drawSignals(app, g, H, k, th)
            for a = app.sigAx, cla(a); legend(a, "off"); hold(a, "on"); grid(a, "on"); end
            ax = app.sigAx(1);
            plot(ax, th, 100 * H.z(k, g), "-", "Color", [1 1 1], "LineWidth", 1.5, "DisplayName", "true");
            plot(ax, th, 100 * H.zh(k, g), "--", "Color", [0.95 0.45 0.1], "LineWidth", 1.2, "DisplayName", "estimated");
            title(ax, sprintf("Group %d SOC (%%)", g)); legend(ax);
            plot(app.sigAx(2), th, H.i(k)); title(app.sigAx(2), "Pack current (A), discharge +");
            plot(app.sigAx(3), th, H.v(k, g)); title(app.sigAx(3), sprintf("Group %d voltage (V)", g));
            plot(app.sigAx(4), th, H.T(k, :)); title(app.sigAx(4), "Group temperatures (°C)");
            for a = app.sigAx
                xlabel(a, "Simulated time (h)"); cycleMarks(a, th, H.cycle(k), ylim(a)); hold(a, "off");
            end
        end

        function drawPack(app, H, k, th)
            for a = app.packAx, cla(a); legend(a, "off"); hold(a, "on"); grid(a, "on"); end
            z = H.z(k, :); zh = H.zh(k, :); Q = H.Q(k, :); Qe = H.Qe(k, :);
            Vp = sum(H.v(k, :), 2); I = H.i(k); Pw = Vp .* I;
            % series-pack SOC limited by the weakest group (usable charge between the
            % first group reaching empty and the first reaching full); and the average
            sw = @(z, Q) min(z .* Q, [], 2) ./ (min(z .* Q, [], 2) + min((1 - z) .* Q, [], 2));
            a = app.packAx(1);
            yyaxis(a, "left"); plot(a, th, Vp, "-"); ylabel(a, "Pack voltage (V)");
            yyaxis(a, "right"); plot(a, th, I, "-"); ylabel(a, "Current (A)"); title(a, "Pack voltage and current");
            a = app.packAx(2);
            plot(a, th, 100 * sw(z, Q), "-", "Color", [1 1 1], "LineWidth", 1.6, "DisplayName", "true, weakest group");
            plot(a, th, 100 * sw(zh, Qe), "--", "Color", [0.95 0.45 0.1], "LineWidth", 1.3, "DisplayName", "estimated, weakest group");
            plot(a, th, 100 * mean(z, 2), "-", "Color", [0.7 0.7 0.7], "DisplayName", "true, average");
            plot(a, th, 100 * mean(zh, 2), ":", "Color", [0.3 0.6 0.95], "LineWidth", 1.3, "DisplayName", "estimated, average");
            title(a, "Pack SOC (%)"); legend(a, "Location", "best", "FontSize", 8);
            a = app.packAx(3);
            plot(a, th, min(Q, [], 2), "-", "Color", [1 1 1], "LineWidth", 1.6, "DisplayName", "true (smallest group)");
            plot(a, th, min(Qe, [], 2), "--", "Color", [0.95 0.45 0.1], "LineWidth", 1.3, "DisplayName", "estimated");
            title(a, "Pack capacity (Ah)"); legend(a, "Location", "best", "FontSize", 8);
            a = app.packAx(4);
            plot(a, th, 100 * (max(z, [], 2) - min(z, [], 2)), "-", "Color", [1 1 1], "DisplayName", "true");
            plot(a, th, 100 * (max(zh, [], 2) - min(zh, [], 2)), "--", "Color", [0.95 0.45 0.1], "DisplayName", "estimated");
            title(a, "SOC spread across groups (percentage points)"); legend(a, "Location", "best", "FontSize", 8);
            a = app.packAx(5);
            plot(a, th, max(H.T(k, :), [], 2), "-", "DisplayName", "max"); plot(a, th, min(H.T(k, :), [], 2), "-", "DisplayName", "min");
            title(a, "Group temperature range (°C)"); legend(a, "Location", "best", "FontSize", 8);
            for a = app.packAx, xlabel(a, "Simulated time (h)"); hold(a, "off"); end
            % summary at the view time (energy from the history, every few seconds)
            n = find(k, 1, "last"); [~, wg] = min(z(end, :) .* Q(end, :));
            eOut = trapz(H.t(k), max(Pw, 0)) / 3600; eIn = trapz(H.t(k), max(-Pw, 0)) / 3600;
            names = ["Pack voltage (V)"; "Current (A)"; "Power (W)"; "Energy out / in (Wh, from history)"; ...
                "SOC, weakest group: true / est (%)"; "SOC, average: true / est (%)"; "Capacity, smallest group: true / est (Ah)"; ...
                "Weakest group (lowest remaining charge)"; "SOHq min / SOHr min (%)"; "EFC (mean)"; "Cycle"];
            vals = [sprintf("%.2f", Vp(end)); sprintf("%.2f", I(end)); sprintf("%.0f", Pw(end)); sprintf("%.0f / %.0f", eOut, eIn); ...
                sprintf("%.2f / %.2f", 100 * sw(z(end, :), Q(end, :)), 100 * sw(zh(end, :), Qe(end, :))); ...
                sprintf("%.2f / %.2f", 100 * mean(z(end, :)), 100 * mean(zh(end, :))); ...
                sprintf("%.3f / %.3f", min(Q(end, :)), min(Qe(end, :))); sprintf("%d", wg); ...
                sprintf("%.2f / %.2f", 100 * min(H.sohq(n, :)), 100 * min(H.sohr(n, :))); sprintf("%.2f", mean(H.efc(n, :))); ...
                sprintf("%d", H.cycle(n))];
            app.packTable.Data = table(names, vals, 'VariableNames', ["Quantity" "Value"]);
        end

        function drawAgeing(app, g, H, k, th)
            for a = app.ageAx, cla(a); legend(a, "off"); hold(a, "on"); grid(a, "on"); end
            a = app.ageAx(1); plot(a, th, 100 * H.sohq(k, :), "Color", [0.6 0.6 0.6]); plot(a, th, 100 * H.sohq(k, g), "Color", [0.95 0.45 0.1], "LineWidth", 1.8);
            yline(a, 70, "--", "end of life 70 %", "Color", [0.9 0.3 0.3]); title(a, "SOHq = Q / Q_{new} (%), all groups, selected in orange");
            a = app.ageAx(2); plot(a, th, 100 * H.sohr(k, :), "Color", [0.6 0.6 0.6]); plot(a, th, 100 * H.sohr(k, g), "Color", [0.95 0.45 0.1], "LineWidth", 1.8);
            title(a, "SOHr = R_{new} / R (%)");
            a = app.ageAx(3); plot(a, th, H.efc(k, :), "Color", [0.6 0.6 0.6]); plot(a, th, H.efc(k, g), "Color", [0.95 0.45 0.1], "LineWidth", 1.8);
            title(a, "Equivalent full cycles");
            a = app.ageAx(4);
            plot(a, th, H.Q(k, g), "-", "Color", [1 1 1], "LineWidth", 1.8, "DisplayName", "true");
            plot(a, th, H.Qe(k, g), "--", "Color", [0.95 0.45 0.1], "LineWidth", 1.4, "DisplayName", "estimated");
            title(a, sprintf("Group %d capacity (Ah)", g)); legend(a, "Location", "best");
            for a = app.ageAx, xlabel(a, "Simulated time (h)"); cycleMarks(a, th, H.cycle(k), ylim(a)); hold(a, "off"); end
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

function y = ifelse(c, a, b)
if c, y = a; else, y = b; end
end

function shadePhases(ax, th, mode, inLegend)
% phase strip along the top of the axes: grey = rest, green = charge, none = discharge
if isempty(mode), return, end
col = {[0.55 0.55 0.55], [0.35 0.75 0.35]}; nmz = ["rest" "charge"];
for c = 1:2
    if c == 1, on = ismember(mode, [0 2 4]); else, on = mode == 3; end
    d = diff([0; on(:); 0]); s0 = find(d == 1); s1 = find(d == -1) - 1;
    for j = 1:numel(s0)
        x0 = th(s0(j)); x1 = th(min(s1(j) + 1, numel(th)));
        h = patch(ax, [x0 x1 x1 x0], [16 16 30 30], col{c}, "FaceAlpha", 0.7, "EdgeColor", "none", ...
            "DisplayName", nmz(c));
        if j > 1 || ~inLegend, h.HandleVisibility = "off"; end
    end
end
end

function cycleMarks(ax, th, cyc, yl)
% dotted line at the start of each schedule cycle, labelled "C n" (thinned when many)
if isempty(cyc), return, end
st = find(diff([0; cyc(:)]) > 0);
if isempty(st), return, end
step = max(1, ceil(numel(st) / 15));
hold(ax, "on");
for j = 1:numel(st)
    x = th(st(j));
    plot(ax, [x x], yl, ":", "Color", [0.75 0.75 0.75], "LineWidth", 0.8, "HandleVisibility", "off");
    if mod(j - 1, step) == 0
        text(ax, x, yl(2), " C" + cyc(st(j)), "Color", [0.85 0.85 0.85], "FontSize", 8, ...
            "VerticalAlignment", "top", "Clipping", "on");
    end
end
end
