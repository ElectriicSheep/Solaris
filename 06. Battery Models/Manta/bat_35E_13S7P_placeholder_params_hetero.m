%% bat_35E_13S7P_placeholder_params_hetero.m
% Heterogeneous version of bat_35E_13S7P_placeholder_params.m: the same nominal
% cell, with small module-to-module and cell-to-cell differences.
%
% SYNTHETIC PLACEHOLDER VALUES - NOT MEASURED. The spreads below are chosen to be
% small (a few percent), the order of magnitude reported for new cells from one
% production batch (e.g. Rumpf et al., J. Energy Storage, 2017; Schuster et al.,
% J. Power Sources, 2015). They are not fitted to those studies or to the 35E.
% Replace with measured spreads before reporting results.
%
% What can vary, and at what level (limit of the generated Simscape Battery blocks):
%   per MODULE block (7 sets; the two parallel groups in one 2S7P module stay identical):
%     capacity, R0, R1, tau1 (scale factors on the whole table), OCV (offset on the
%     whole curve), thermal mass
%   per CELL (91 values):
%     AmbientResistance (cell to ambient), e.g. differences in airflow and contact
% Cell-to-cell and slice-to-slice conduction (cellPairs_*, axialLink_*) is unchanged.
%
% Each factor is drawn from a normal distribution with the standard deviation below,
% truncated at +/-2 sigma, from a fixed seed, so every run gives the same pack.
% Change PLANT_variationSeed for a different (equally plausible) pack.
%
% Output, in addition to everything the homogeneous file creates:
%   batMod(1..7)     parameter sets read by the module blocks
%   PLANT_variation  table of the factors per module and the groups they apply to
%                    (ground truth for checking the BMS SOC/SOH estimates)

bat_35E_13S7P_placeholder_params;   % nominal values and homogeneous batMod

%% Spreads (1 standard deviation)  PLACEHOLDERS
hetSigma.capacity   = 0.010;   % 1 %    capacity
hetSigma.R0         = 0.030;   % 3 %    ohmic resistance
hetSigma.R1         = 0.050;   % 5 %    polarisation resistance
hetSigma.tau1       = 0.050;   % 5 %    polarisation time constant
hetSigma.ocvOffset  = 0.002;   % 2 mV   OCV offset (whole curve)
hetSigma.thermMass  = 0.030;   % 3 %    thermal mass
hetSigma.ambientR   = 0.100;   % 10 %   cell-to-ambient resistance, per cell

if ~exist("PLANT_variationSeed", "var"), PLANT_variationSeed = 1; end
hetStream = RandStream("mt19937ar", "Seed", PLANT_variationSeed);   % does not touch the global rng
hetDraw   = @(n) max(-2, min(2, randn(hetStream, 1, n)));          % truncated at +/-2 sigma

%% Apply
hetNMod   = numel(batMod);
hetFactor = struct( ...
    "capacity",  1 + hetSigma.capacity  * hetDraw(hetNMod), ...
    "R0",        1 + hetSigma.R0        * hetDraw(hetNMod), ...
    "R1",        1 + hetSigma.R1        * hetDraw(hetNMod), ...
    "tau1",      1 + hetSigma.tau1      * hetDraw(hetNMod), ...
    "ocvOffset",     hetSigma.ocvOffset * hetDraw(hetNMod), ...
    "thermMass", 1 + hetSigma.thermMass * hetDraw(hetNMod));
for hetM = 1:hetNMod
    batMod(hetM).BatteryCapacityCell           = batMod(hetM).BatteryCapacityCell    * hetFactor.capacity(hetM);
    batMod(hetM).R0ThermalCell                 = batMod(hetM).R0ThermalCell          * hetFactor.R0(hetM);
    batMod(hetM).R1ThermalCell                 = batMod(hetM).R1ThermalCell          * hetFactor.R1(hetM);
    batMod(hetM).Tau1ThermalCell               = batMod(hetM).Tau1ThermalCell        * hetFactor.tau1(hetM);
    batMod(hetM).OpenCircuitVoltageThermalCell = batMod(hetM).OpenCircuitVoltageThermalCell + hetFactor.ocvOffset(hetM);
    batMod(hetM).BatteryThermalMassCell        = batMod(hetM).BatteryThermalMassCell * hetFactor.thermMass(hetM);
    nCellsM = numel(batMod(hetM).AmbientResistance);
    batMod(hetM).AmbientResistance             = batMod(hetM).AmbientResistance .* (1 + hetSigma.ambientR * hetDraw(nCellsM));
end

%% Record the pack for evaluation (ground truth for the BMS estimates)
hetGroups = ["1-2" "3-4" "5-6" "7-8" "9-10" "11-12" "13"]';
PLANT_variation = table((1:hetNMod)', hetGroups, ...
    100*(hetFactor.capacity' - 1), 100*(hetFactor.R0' - 1), 100*(hetFactor.R1' - 1), ...
    100*(hetFactor.tau1' - 1), 1e3*hetFactor.ocvOffset', 100*(hetFactor.thermMass' - 1), ...
    'VariableNames', ["Module","Groups","Capacity_pct","R0_pct","R1_pct","Tau1_pct", ...
                      "OCVoffset_mV","ThermalMass_pct"]);
PLANT_variation.Properties.Description = sprintf( ...
    "Placeholder module-to-module variation, seed %d (bat_35E_13S7P_placeholder_params_hetero.m)", ...
    PLANT_variationSeed);
fprintf("Heterogeneous cells (placeholder spreads, seed %d)\n", PLANT_variationSeed);

clear hetSigma hetStream hetDraw hetNMod hetFactor hetM nCellsM hetGroups
