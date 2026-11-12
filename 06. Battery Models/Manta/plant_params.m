%% plant_params.m
% Plant parameters, run by bmsTestPlatform's InitFcn (before sensor_params).
% Chooses the cell parameter set:
%   PLANT_cellVariation = 1  heterogeneous placeholder cells (default)
%                             bat_35E_13S7P_placeholder_params_hetero.m
%   PLANT_cellVariation = 0  identical placeholder cells
%                             bat_35E_13S7P_placeholder_params.m
% To override for one session or test, set PLANT_cellVariation in the base
% workspace before simulating, and clear it afterwards.

if ~exist("PLANT_cellVariation", "var"), PLANT_cellVariation = 1; end
if PLANT_cellVariation
    bat_35E_13S7P_placeholder_params_hetero;
else
    bat_35E_13S7P_placeholder_params;
end
