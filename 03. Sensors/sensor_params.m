%% sensor_params.m
% Parameters for the BMS sensor layer (simulation only, not deployed).
% One tube: 13 group voltages, 1 pack current, 26 temperatures (2 per group).
%
% ALL ERROR VALUES ARE PLACEHOLDERS (typical orders of magnitude for a
% monitoring IC, a shunt + power-monitor IC and glued NTC thermistors).
% Replace with datasheet values once parts are chosen.
%
% Set sens.enableErrors = 0 for ideal sensors (baseline runs).

sens.enableErrors = 1;      % 1 = apply errors, 0 = ideal sensors
rng(1);                     % fixed seed: same per-channel offsets every run

%% Sample times (s)
sens.Ts_V = 0.1;            % group voltages
sens.Ts_I = 0.1;            % pack current
sens.Ts_T = 1.0;            % temperatures

%% Group voltages (13 channels)
nV = 13;
sens.V_offset = sens.enableErrors * (2e-3*rand(nV,1) - 1e-3);  % V, fixed per channel, +/-1 mV
sens.V_gain   = 1 + sens.enableErrors * (1e-3*rand(nV,1) - 5e-4); % -, +/-0.05 %
sens.V_noiseVar = sens.enableErrors * (0.5e-3)^2;   % V^2, 0.5 mV RMS
sens.V_lsb    = 100e-6;                             % V, quantisation step
sens.V_seed   = 100 + (1:nV)';                      % noise seeds

%% Pack current (1 channel). Sign: same as the plant current sensor.
sens.I_offset   = sens.enableErrors * 0.02;         % A, fixed offset (20 mA)
sens.I_gain     = 1 + sens.enableErrors * 0.002;    % -, +0.2 % (shunt tolerance)
sens.I_noiseVar = sens.enableErrors * (0.01)^2;     % A^2, 10 mA RMS
sens.I_lsb      = 1e-3;                             % A, quantisation step
sens.I_seed     = 200;

%% Temperatures (26 channels, 2 per group)
% Indices into the battery's 91-element batteryTemperature vector:
% module k occupies (k-1)*14 + (1..14); module 7 (1S7P) is 85..91.
% Per group: [buried cell, outer cell] = model cells 5 and 1 (CSV 5 and 6)
% in parallel assembly 1, model cells 12 and 8 (CSV 10 and 9) in assembly 2.
% CHECK the 91-element order with a one-hot-cell run before relying on it.
idx = zeros(13,2);
for g = 1:13
    m = ceil(g/2);  off = (m-1)*14;
    if mod(g,2) == 1, idx(g,:) = off + [5 1];    % assembly 1 of the module
    else,             idx(g,:) = off + [12 8];   % assembly 2 of the module
    end
end
sens.T_index    = reshape(idx',[],1);               % 26x1: g1 buried, g1 outer, g2 buried, ...
nT = numel(sens.T_index);
sens.T_tau      = 10;                               % s, thermistor lag (glued to cell)
sens.T_offset   = sens.enableErrors * (1.0*rand(nT,1) - 0.5);  % K, +/-0.5 K per channel
sens.T_noiseVar = sens.enableErrors * (0.05)^2;     % K^2, 0.05 K RMS
sens.T_lsb      = 0.1;                              % K, quantisation step
sens.T_seed     = 300 + (1:nT)';

clear nV nT idx g m off
