%% temperaturePlot_Pack.m
% Simulates the battery test model and shows cell temperatures on the
% 3-D battery chart.
%
% Edit the four settings below to match your files and model.

import simscape.battery.builder.*

%% Settings
modelName     = "batteryTester";            % Simulink model (without .slx)
batteryMat    = "bat_13S7P_detailed.mat";   % Battery object saved by the library build
batteryVar    = "";                         % Variable name in the MAT-file ("" = use the only one)
batteryBlock  = "battery_13S7P";            % Battery block name in the model ("" = find it)

%% Load the battery object
s = load(batteryMat);
if batteryVar == ""
    names = fieldnames(s);
    assert(isscalar(names), ...
        "The MAT-file has more than one variable. Set batteryVar to one of: %s", ...
        strjoin(names, ", "));
    batteryVar = names{1};
end
myBattery = s.(batteryVar);
fprintf("Battery object: %s (%s)\n", batteryVar, class(myBattery));

%% Enable full Simscape logging
load_system(modelName);
set_param(modelName, "SimscapeLogType", "all");
set_param(modelName, "SimscapeLogLimitData", "off");   % keep the whole run

%% Simulate
tic
out = sim(modelName);
fprintf("Simulation time: %.1f s\n", toc);

%% Find the battery block in the log
logNames = string(fieldnames(out.simlog));
if batteryBlock == ""
    % Use the block whose name matches the battery object's Name, if present
    match = logNames(logNames == string(myBattery.Name));
    assert(isscalar(match), ...
        "Could not find the battery block automatically. Set batteryBlock to one of: %s", ...
        strjoin(logNames, ", "));
    batteryBlock = match;
end
assert(any(logNames == batteryBlock), ...
    "Block '%s' not in the log. Options: %s", batteryBlock, strjoin(logNames, ", "));

%% Create battery simulation log object
batterySimLog = BatterySimulationLog(myBattery, out.simlog.(batteryBlock));
batterySimLog.SelectedVariable     = "batteryTemperature";
batterySimLog.SelectedVariableUnit = "degC";
disp(batterySimLog)

%% Visualise
f = uifigure("Color", "w", "Name", "Cell temperatures");
g = uigridlayout(f, [1, 1]);
packChart = BatterySimulationChart(Parent = g, BatterySimulationLog = batterySimLog);
cb = colorbar(packChart);
colormap(packChart, turbo);   % built-in colormap (blue = cool, red = hot)
ylabel(cb, batterySimLog.SelectedVariable + " (" + batterySimLog.SelectedVariableUnit + ")");
