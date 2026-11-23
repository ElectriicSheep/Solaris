%% bat4s_params.m
% Parameters for a 4S1P Samsung INR18650-35E pack (four single cells in
% series), used with the BQ76952EVM block.
%
% SYNTHETIC PLACEHOLDER VALUES - NOT MEASURED, NOT FROM A PUBLISHED SOURCE.
% Cell values are copied from Manta/bat_35E_13S7P_placeholder_params.m
% (section 2). Replace them with HPPC results from the four cells of the
% hardware pack once those are characterised.
%
% Notes:
% - OCV, R0, R1 and Tau1 are identical at both temperature breakpoints, so
%   the electrical model has NO temperature dependence.
% - Thermal mass is an estimate (900 J/kg/K x 0.048 kg).
% - AmbientResistance (105 K/W) assumes the cells sit inside the hull tube.
%   A 4S pack on an open bench will differ: treat it as unknown.
% - Field names match the Battery Builder / Simscape Battery names so each
%   maps directly to a block dialog prompt.
%
% Creates one struct, bat4s, in the workspace this file is run from.

bat4s = struct();
bat4s.nS = 4;      % cells in series
bat4s.nP = 1;      % cells in parallel

%% Cell values (identical for all four cells for now)
soc  = 0:0.1:1;                 % SOC breakpoints
temp = [263.15 333.15];         % Temperature breakpoints, K (-10 to 60 C)

ocv  = [2.650 3.380 3.510 3.590 3.655 3.725 3.795 3.875 3.970 4.075 4.200]';  % V
r0   = [0.058 0.046 0.041 0.038 0.037 0.036 0.036 0.035 0.035 0.034 0.034]';  % Ohm
r1   = [0.125 0.068 0.045 0.032 0.028 0.025 0.024 0.022 0.021 0.018 0.015]';  % Ohm
tau1 = [81.3  81.6  81.0  80.0  81.2  77.5  70.8  61.6  54.6  44.1  31.5 ]';  % s

bat4s.cell.BatteryCapacityCell                  = 3.35;              % A*hr, datasheet minimum at 0.2C
bat4s.cell.SOCBreakpointsCell                   = soc;
bat4s.cell.TemperatureBreakpointsCell           = temp;
bat4s.cell.OpenCircuitVoltageThermalCell        = repmat(ocv,1,2);   % OCV(SOC,T), V
bat4s.cell.VoltageRangeCell                     = [0, inf];          % V, limits left to the BMS
bat4s.cell.ResistanceSOCBreakpointsCell         = soc;
bat4s.cell.ResistanceTemperatureBreakpointsCell = temp;
bat4s.cell.R0ThermalCell                        = repmat(r0,1,2);    % R0(SOC,T), Ohm
bat4s.cell.R1ThermalCell                        = repmat(r1,1,2);    % R1(SOC,T), Ohm
bat4s.cell.Tau1ThermalCell                      = repmat(tau1,1,2);  % Tau1(SOC,T), s
bat4s.cell.BatteryThermalMassCell               = 43.2;              % J/K, estimate
bat4s.cell.AmbientResistance                    = 105;               % K/W per cell, PLACEHOLDER

%% Initial conditions and ambient
bat4s.soc0 = [0.80 0.80 0.80 0.80];   % initial SOC per cell, 0-1 (cell 1 = bottom, next to BAT-)
bat4s.T0   = 298.15;                  % initial cell temperature, K (25 C)
bat4s.Tamb = 298.15;                  % ambient temperature, K (25 C)

clear soc temp ocv r0 r1 tau1
