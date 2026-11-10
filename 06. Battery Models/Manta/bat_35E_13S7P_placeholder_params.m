%% bat_35E_13S7P_placeholder_params.m
% Parameters for the 13S7P Samsung INR18650-35E battery (one tube).
%
% SYNTHETIC PLACEHOLDER VALUES - NOT MEASURED, NOT FROM A PUBLISHED SOURCE.
% Use for model testing only. Do not report results from these values as
% representative of a real INR18650-35E.
%
% How it works:
%   1. Runs the parameter file Battery Builder generated, so every field the
%      block needs exists.
%   2. Overwrites the cell values below in every ModuleType and
%      ParallelAssemblyType struct.
%   Any field not set here keeps the generated default. Rebuilding the
%   library therefore cannot overwrite your tables, and new fields from a
%   rebuild are picked up automatically.
%
% Notes:
% - OCV, R0, R1 and Tau1 are identical at both temperature breakpoints, so
%   the electrical model has NO temperature dependence.
% - Thermal mass is an estimate (900 J/kg/K x 0.048 kg).
% - AmbientResistance (cell to internal air) is a placeholder.

%% 1. Generated file (change if your library name differs)
generatedParamFile = 'bat_13S7P_detailed_param';
run(generatedParamFile);

%% Initial conditions (used by every module once setBatteryInitialConditions.m has been run)
SOC0 = 1;          % initial state of charge, 0-1
T0   = 288.15;     % initial cell temperature, K (15 C; match the ambient source)

%% 2. Cell values
soc  = 0:0.1:1;                 % SOC breakpoints
temp = [263.15 333.15];         % Temperature breakpoints, K (-10 to 60 C)

ocv  = [2.650 3.380 3.510 3.590 3.655 3.725 3.795 3.875 3.970 4.075 4.200]';  % V
r0   = [0.058 0.046 0.041 0.038 0.037 0.036 0.036 0.035 0.035 0.034 0.034]';  % Ohm
r1   = [0.125 0.068 0.045 0.032 0.028 0.025 0.024 0.022 0.021 0.018 0.015]';  % Ohm
tau1 = [81.3  81.6  81.0  80.0  81.2  77.5  70.8  61.6  54.6  44.1  31.5 ]';  % s

cellParams.BatteryCapacityCell                  = 3.35;            % A*hr, datasheet minimum at 0.2C
cellParams.SOCBreakpointsCell                   = soc;
cellParams.TemperatureBreakpointsCell           = temp;
cellParams.OpenCircuitVoltageThermalCell        = repmat(ocv,1,2);
cellParams.VoltageRangeCell                     = [0, inf];        % V, limits left to the BMS
cellParams.ResistanceSOCBreakpointsCell         = soc;
cellParams.ResistanceTemperatureBreakpointsCell = temp;
cellParams.R0ThermalCell                        = repmat(r0,1,2);
cellParams.R1ThermalCell                        = repmat(r1,1,2);
cellParams.Tau1ThermalCell                      = repmat(tau1,1,2);
cellParams.BatteryThermalMassCell               = 43.2;            % J/K, estimate
% Cell to INTERNAL AIR (the AmbH port -> tubeAmbient Air node), K/W. PLACEHOLDER.
% Natural convection h = 5 W/m^2/K over half the cell side area
% (assumes the carriage covers the other half): 1/(5 x 0.5 x 3.80e-3 m^2) = ~105 K/W.
% Outer-row cells also have a path to the hull through the hullContact_* blocks.
cellParams.AmbientResistance                    = 105;
% Cell-to-cell and slice-to-slice heat paths are NOT set here: they are the
% R parameters of the cellPairs_* and axialLink_* blocks (placeholders).

%% 3. Apply to every generated struct
paramNames = who('-regexp','^(ModuleType|ParallelAssemblyType)\d+$');
assert(~isempty(paramNames), ...
    'No ModuleType/ParallelAssemblyType variables found. Check generatedParamFile.')
fieldsToSet = fieldnames(cellParams);
for k = 1:numel(paramNames)
    s = eval(paramNames{k});
    for j = 1:numel(fieldsToSet)
        s.(fieldsToSet{j}) = cellParams.(fieldsToSet{j});
    end
    eval([paramNames{k} ' = s;']);
end

%% 4. Optional: different values per slice (ModuleType1 = slice 1 ... ModuleType7 = half slice)
% ModuleType1.AmbientResistance = 20;
% ModuleType7.AmbientResistance = 20;

% SOC0 and T0 are kept for the module initial conditions
clear generatedParamFile soc temp ocv r0 r1 tau1 cellParams paramNames fieldsToSet s j k
