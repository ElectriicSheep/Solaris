function P = ecmParams(opts)
%ECMPARAMS Parameters for the offline adaptive-ECM test (ecmOffline.slx).
%
%   P = ecmParams                      defaults (seed 1, initial errors 2-5 %)
%   P = ecmParams(Seed=3, ErrRange=[0.02 0.05], ErrShape="smooth", Noise=true, InitTables=S, ...
%                 Profile="sample3", LoadScale=3, Spread=true)
%
% PLANT (truth). 13 group-level equivalent circuits, one per parallel group (7P).
%   Each group's tables are built from its 7 cells: OCV and tau1 are the average of
%   the cells, R0 and R1 are the parallel combination, capacity and thermal mass
%   are the sum, and the cell-to-ambient resistances combine in parallel.
%   The cells come from bat_35E_13S7P_placeholder_params_hetero.m (SYNTHETIC
%   PLACEHOLDER values, module-to-module spread, PLANT_variationSeed). At present
%   the 7 cells of a group are identical, so the group model is electrically exact.
%   The electrical tables have NO temperature dependence (identical at both
%   temperature breakpoints), as in the cell file.
%   Thermal: one lumped mass per group, I^2*R0 + v1^2/R1 heating, loss to a fixed
%   ambient. There is NO group-to-group conduction (the detailed plant has some),
%   so temperatures are indicative only.
%
% ESTIMATOR. Tables of R0, R1 and tau1 over SOC x temperature per group, plus one
%   capacity per group. They start at the true values scaled by (1 + d), with one
%   d per parameter per group, |d| uniform in ErrRange and a random sign, drawn
%   from a fixed seed. The OCV curve is the NOMINAL cell curve (without the module
%   offsets), so the estimator does not know the per-module OCV offsets (+/- a few mV).
%
% Options
%   Seed        seed for the initial errors (default 1)
%   ErrRange    [min max] relative initial error (default [0.02 0.05])
%   Noise       true adds sensor noise and a current offset (default false)
%   InitTables  struct with fields r0, r1, tau (11x6x13), Q (1x13) and count
%               (11x6x13x3) from a previous run (ecmSaveTables); replaces the
%               perturbed start (restart test)
%   PlantSeed   PLANT_variationSeed for the cell spread (default 1)
%   ErrShape    shape of the starting errors over each group's SOC x T table:
%               "group"   one error per parameter per group (whole table scaled)
%               "smooth"  a smooth surface over SOC x T, |d| in ErrRange, one sign
%                         per parameter per group (like a table from another cell)
%               "node"    an independent error at every table point (|d| in ErrRange,
%                         random sign): the hardest case for spreading
%   Profile     discharge load: "cycleA" (marine CYCLE A, default) or "sample3"
%               (24Vsample 3.csv: 16.5 s at ~90 Hz, averaged into 0.1 s steps, looped)
%   LoadScale   multiplies the discharge load current (default 1)
%   Spread      true: unvisited table points take the correction ratio of their
%               visited neighbours when the tables are read (default true)
%   IC          per-group initial conditions (struct, fields 1 x 13): soc0, sohq0,
%               sohr0, T0C, cyc0 (equivalent full cycles), and tAmbC (scalar).
%               Missing fields: defaults (0.95, 1, 1, 15 C, 0, 15 C). ecmIcFromCycles
%               fills SOHq/SOHr from the cycle count with the degradation model.
%   TempDep     placeholder Arrhenius temperature dependence of R0, R1, tau1 (default true)
%   Degradation placeholder ageing: capacity fade and resistance growth with charge
%               throughput and time, Arrhenius in temperature (default true)
%   ErrBase     "current": estimator starts from the true values at the start
%               (incl. the set SOH) x (1 + d); "new": from new-cell values x (1 + d)
%   NCycles     stop after this many schedule cycles (default inf)
%   AgeingScale multiplies the ageing rates: 10 reaches end of life in ~60 EFC instead
%               of ~600 (fast-forward; the estimator then sees a 10x faster drift)
%   Method      parameter identification feeding the tables: "ffrls" (R0 FFRLS on
%               differences + IV-FFRLS for the RC branch, default) or "dekf" (parameter
%               filter of a dual EKF, after Plett 2004). Same state EKF, tables,
%               spreading and capacity estimator in both.
%
% SOH definitions: SOHq = Q / Q_new, SOHr = R_new / R (both 1 when new, falling).
% End of life: SOHq = 0.7.

arguments
    opts.Seed (1,1) double = 1
    opts.ErrRange (1,2) double = [0.02 0.05]
    opts.Noise (1,1) logical = false
    opts.InitTables = []
    opts.PlantSeed (1,1) double = 1
    opts.ErrShape (1,1) string {mustBeMember(opts.ErrShape, ["group" "smooth" "node"])} = "group"
    opts.Profile (1,1) string {mustBeMember(opts.Profile, ["cycleA" "ideal"])} = "cycleA"
    opts.LoadScale (1,1) double = 1
    opts.Spread (1,1) logical = true
    opts.IC = []                       % struct: soc0, sohq0, sohr0, T0C, cyc0 (1 x 13), tAmbC
    opts.TempDep (1,1) logical = true  % temperature dependence of R0, R1, tau1 (placeholder Arrhenius)
    opts.Degradation (1,1) logical = true
    opts.ErrBase (1,1) string {mustBeMember(opts.ErrBase, ["current" "new"])} = "current"
    opts.NCycles (1,1) double = inf    % stop after this many schedule cycles
    opts.Method (1,1) string {mustBeMember(opts.Method, ["ffrls" "dekf"])} = "ffrls"
    opts.AgeingScale (1,1) double = 1  % multiplies all ageing rates (fast-forward ageing)
    opts.TrendQ (1,1) logical = false  % capacity: alpha-beta trend vs charge throughput (derivative test)
end

here = fileparts(mfilename("fullpath"));
root = fileparts(here);

%% Cells (run the cell file in a private workspace)
cells = loadCells(fullfile(root, "06. Battery Models", "Manta"), opts.PlantSeed);
batMod = cells.batMod;

P.nG = 13;
P.Ts   = 0.1;      % s, sensor and estimator base rate (chip read rate on the Pi)
P.TsRc = 1.0;      % s, rate of the RC-branch identification (see adaptiveEcm)
P.TsLog = 1.0;     % s, logging interval for evaluation and the app
P.logSensorPoints = 1;   % samples of the 0.1 s sensor signals kept (inf to check against dev/ecmPrototype)

%% Group membership: module m -> groups
modGroups = {[1 2], [3 4], [5 6], [7 8], [9 10], [11 12], 13};
socBp = batMod(1).SOCBreakpointsCell(:)';                 % 0:0.1:1
tBpK  = batMod(1).TemperatureBreakpointsCell(:)';         % [263.15 333.15]
nS = numel(socBp);  nT = numel(tBpK);

ocv = zeros(nS, nT, P.nG); r0 = ocv; r1 = ocv; tau = ocv;
Q = zeros(1, P.nG); Cth = Q; Rth = Q;
for m = 1:numel(batMod)
    b = batMod(m);
    nPerGroup = 7;
    for k = 1:numel(modGroups{m})
        g = modGroups{m}(k);
        % 7 cells of this group (cells of one module are identical except AmbientResistance)
        idx = (k-1)*nPerGroup + (1:nPerGroup);              % cell order within the module, ASSUMED group by group
        cOcv = repmat(b.OpenCircuitVoltageThermalCell, 1, 1, nPerGroup);
        cR0  = repmat(b.R0ThermalCell,   1, 1, nPerGroup);
        cR1  = repmat(b.R1ThermalCell,   1, 1, nPerGroup);
        cTau = repmat(b.Tau1ThermalCell, 1, 1, nPerGroup);
        ocv(:,:,g) = mean(cOcv, 3);
        tau(:,:,g) = mean(cTau, 3);
        r0(:,:,g)  = 1 ./ sum(1 ./ cR0, 3);
        r1(:,:,g)  = 1 ./ sum(1 ./ cR1, 3);
        Q(g)   = nPerGroup * b.BatteryCapacityCell;
        Cth(g) = nPerGroup * b.BatteryThermalMassCell;
        Rth(g) = 1 / sum(1 ./ b.AmbientResistance(idx));
    end
end

% Temperature dependence (PLACEHOLDER): the cell tables are taken as 25 C values and
% scaled by exp(Ea/Rg * (1/T - 1/Tref)) on a 10 C grid. Ea: R0 15, R1 30, tau1 10 kJ/mol.
% OCV and capacity: no temperature dependence.
P.plant.tempDep = opts.TempDep;
P.plant.Ea = struct("r0", 15e3, "r1", 30e3, "tau", 10e3);  P.plant.Tref = 25;
tBpC = -10:10:60;
arr = @(Ea, TC) exp(Ea / 8.314 * (1 ./ (TC + 273.15) - 1 / (P.plant.Tref + 273.15)));
fT = @(nm) reshape(opts.TempDep * arr(P.plant.Ea.(nm), tBpC) + ~opts.TempDep * ones(size(tBpC)), 1, []);
P.plant.arr = arr;
P.plant.socBp = socBp;
P.plant.tBpC  = tBpC;
nTp = numel(tBpC);
P.plant.ocv = repmat(ocv(:, 1, :), 1, nTp, 1);
P.plant.r0  = r0(:, 1, :) .* fT("r0");
P.plant.r1  = r1(:, 1, :) .* fT("r1");
P.plant.tau = tau(:, 1, :) .* fT("tau");
P.plant.Qnew = Q;
P.plant.Q   = Q;    P.plant.Cth = Cth; P.plant.Rth = Rth;

% Degradation (PLACEHOLDER). States per group: equivalent full cycles (EFC = Ah
% throughput / (2 Q_new)), capacity loss L (SOHq = 1 - L) and resistance growth G
% (R = R_new (1 + G), SOHr = 1/(1 + G)). Rates at 25 C, Arrhenius in temperature:
%   cycling   dL/dEFC = 0.3/600 (70 % after 600 EFC), dG/dEFC = 0.6/600 (+60 %)
%   calendar  dL/dt = 2 %/year, dG/dt = 3 %/year
% tau1 is not aged.
D.on = opts.Degradation;
D.eolSohq = 0.7;
D.kQcyc = 0.3 / 600;  D.kRcyc = 0.6 / 600;
D.kQcal = 0.02 / (365 * 86400);  D.kRcal = 0.03 / (365 * 86400);
D.EaCyc = 20e3;  D.EaCal = 50e3;
D.scale = opts.AgeingScale;
D.kQcyc = D.kQcyc * D.scale;  D.kRcyc = D.kRcyc * D.scale;  D.kQcal = D.kQcal * D.scale;  D.kRcal = D.kRcal * D.scale;
P.deg = D;

% Initial conditions per group (defaults, then opts.IC)
ic = struct("soc0", 0.95 * ones(1, P.nG), "sohq0", ones(1, P.nG), "sohr0", ones(1, P.nG), ...
    "T0C", 15 * ones(1, P.nG), "cyc0", zeros(1, P.nG), "tAmbC", 15);
if ~isempty(opts.IC)
    for f = string(fieldnames(opts.IC))'
        v = opts.IC.(f);
        if f ~= "tAmbC" && isscalar(v), v = v * ones(1, P.nG); end
        ic.(f) = reshape(v, 1, []);
    end
end
P.ic = ic;
P.plant.tAmbC = ic.tAmbC;
P.plant.soc0  = ic.soc0;
P.plant.T0C   = ic.T0C;
P.plant.L0    = 1 - ic.sohq0;
P.plant.G0    = 1 ./ ic.sohr0 - 1;
P.plant.efc0  = ic.cyc0;
P.plant.variation = cells.PLANT_variation;
P.plant.cellSource = "bat_35E_13S7P_placeholder_params_hetero.m (SYNTHETIC PLACEHOLDER)";

%% Thermistors: 7, one per two groups, group 13 alone (as on the BQ76952)
P.sens.groupTherm = [1 1 2 2 3 3 4 4 5 5 6 6 7];   % thermistor read by each group
M = zeros(7, P.nG);
for g = 1:P.nG, M(P.sens.groupTherm(g), g) = 1; end
P.sens.thermMap = M ./ sum(M, 2);                    % thermistor = mean of its groups
P.sens.vLsb = 1e-3;  P.sens.iLsb = 0.01;  P.sens.tLsb = 0.1;   % BQ76952 reporting resolution
if opts.Noise
    P.sens.vNoise = 1e-3;  P.sens.iNoise = 0.02;  P.sens.iOffset = 0.02;  P.sens.tNoise = 0.2;
else
    P.sens.vNoise = 0;     P.sens.iNoise = 0;     P.sens.iOffset = 0;     P.sens.tNoise = 0;
end
P.sens.noiseSeed = 101;

%% Load schedule
switch opts.Profile
    case "cycleA"
        lp = load(fullfile(root, "01. LoadProfiles", "marineCycle_a.mat"), "marine_cycle").marine_cycle;
        prof = lp(2, :)';                                % A, pack, discharge positive, 0.1 s samples
    case "ideal"
        prof = ecmIdealProfile(P.Ts);
end
P.load.profile = opts.LoadScale * prof;
P.load.profileName = opts.Profile;  P.load.scale = opts.LoadScale;
P.load.N       = numel(P.load.profile);
P.load.iChg    = 7;          % A, constant-current charge (0.3C)
P.load.socLow  = 0.10;       % end discharge when the lowest group reaches this (true SOC)
P.load.socHigh = 0.95;       % end charge when the highest group reaches this
P.load.vMax    = 4.20;       % V, or when any group reaches this voltage
P.load.tRest0  = 600;        % s, rest at the start
P.load.tRest   = 1800;       % s, rest after each discharge and charge
P.load.nCycles = opts.NCycles;

%% Estimator grid and OCV (nominal cell curve)
P.est.socBp = socBp;
P.est.tBpC  = [0 10 20 30 40 50];
nTe = numel(P.est.tBpC);
cellsNom = loadCells(fullfile(root, "06. Battery Models", "Manta"), opts.PlantSeed, true);
P.est.ocv  = cellsNom.batMod(1).OpenCircuitVoltageThermalCell(:, 1)';
P.est.socOfOcv = socBp;                               % inverse table (OCV is monotonic)
dOcv = gradient(P.est.ocv, socBp);
P.est.dOcv = dOcv;

% True NEW-cell values on the estimator grid (for comparison). At a given time the
% truth is r0, r1 x 1/SOHr(t) and Q x SOHq(t) (tau1 not aged).
fTe = @(nm) reshape(opts.TempDep * arr(P.plant.Ea.(nm), P.est.tBpC) + ~opts.TempDep * ones(1, nTe), 1, []);
tr.r0 = r0(:, 1, :) .* fTe("r0");
tr.r1 = r1(:, 1, :) .* fTe("r1");
tr.tau = tau(:, 1, :) .* fTe("tau");
tr.Q = Q;
P.truth = tr;
% truth at the start (with the set SOH)
g0 = reshape(1 + P.plant.G0, 1, 1, []);
tr0.r0 = tr.r0 .* g0;  tr0.r1 = tr.r1 .* g0;  tr0.tau = tr.tau;  tr0.Q = Q .* (1 - P.plant.L0);
P.truth0 = tr0;
if opts.ErrBase == "new", base = tr; else, base = tr0; end

% Initial errors (relative, d): capacity one per group; tables per opts.ErrShape
s = RandStream("mt19937ar", "Seed", opts.Seed);
lo = opts.ErrRange(1);  span = diff(opts.ErrRange);
drawErr = @() (lo + span * rand(s, 1, P.nG)) .* sign(rand(s, 1, P.nG) - 0.5);
P.est.initErr.r0 = drawErr();  P.est.initErr.r1 = drawErr();
P.est.initErr.tau = drawErr(); P.est.initErr.Q = drawErr();
[zz, TT] = ndgrid(socBp, P.est.tBpC);
for nmE = ["r0" "r1" "tau"]
    D = zeros(nS, nTe, P.nG);
    for g = 1:P.nG
        switch opts.ErrShape
            case "group"
                D(:, :, g) = P.est.initErr.(nmE)(g);
            case "smooth"
                % u in [0,1]: two sinusoids, wavelength 0.6-1.2 in SOC and 40-80 C in T
                lz = 0.6 + 0.6 * rand(s);  lt = 40 + 40 * rand(s);  ph = 2*pi*rand(s, 1, 2);
                u = 0.5 + 0.25 * sin(2*pi*zz/lz + ph(1)) + 0.25 * sin(2*pi*TT/lt + ph(2));
                D(:, :, g) = sign(P.est.initErr.(nmE)(g)) * (lo + span * u);
            case "node"
                D(:, :, g) = (lo + span * rand(s, nS, nTe)) .* sign(rand(s, nS, nTe) - 0.5);
        end
    end
    P.est.initErrTable.(nmE) = D;
end
P.est.seed = opts.Seed;  P.est.errRange = opts.ErrRange;  P.est.errShape = opts.ErrShape;  P.est.errBase = opts.ErrBase;
if isempty(opts.InitTables)
    P.est.init.r0  = base.r0  .* (1 + P.est.initErrTable.r0);
    P.est.init.r1  = base.r1  .* (1 + P.est.initErrTable.r1);
    P.est.init.tau = base.tau .* (1 + P.est.initErrTable.tau);
    P.est.init.Q   = base.Q .* (1 + P.est.initErr.Q);
    P.est.init.count = zeros(nS, nTe, P.nG, 3);
    P.est.init.source = sprintf("true x (1 + d), |d| in [%g %g], shape %s, seed %d", opts.ErrRange, opts.ErrShape, opts.Seed);
else
    T0 = opts.InitTables;
    P.est.init.r0 = T0.r0;  P.est.init.r1 = T0.r1;  P.est.init.tau = T0.tau;
    P.est.init.Q = T0.Q;    P.est.init.count = T0.count;
    P.est.init.source = "saved tables from a previous run";
end

% Starting RLS parameters from the starting tables (mid SOC, 10-20 C column)
P.est.init.th0 = reshape(P.est.init.r0(6,2,:), 1, []);
aInit = exp(-P.TsRc ./ reshape(P.est.init.tau(6,2,:), 1, []));
P.est.init.thRc = [aInit; reshape(P.est.init.r1(6,2,:), 1, []) .* (1 - aInit); zeros(1, P.nG)];

P.est.init.phi = [log([reshape(P.est.init.r0(6,2,:), 1, []); reshape(P.est.init.r1(6,2,:), 1, []); ...
    reshape(P.est.init.tau(6,2,:), 1, [])]); zeros(1, P.nG)];

%% Estimator tuning (see adaptiveEcm.slx)
P.est.method    = opts.Method;
P.est.methodId  = double(opts.Method == "dekf") + 1;
% dual EKF parameter filter (log parameters, per 0.1 s step)
P.est.dekfP0    = diag([0.05 0.05 0.05 5e-3].^2);   % 5 % prior std (params), 5 mV (OCV offset)
P.est.dekfQ     = diag([2e-5 2e-5 2e-5 2e-6].^2);   % random walk per step: ~0.4 %/sqrt(h), ~0.4 mV/sqrt(h)
P.est.dekfR     = (2e-3)^2;                      % V^2
P.est.dekfInfo  = (0.01)^2;                      % R0 table writes when its std < 1 %
P.est.dekfInfoRc = (0.03)^2;                     % R1, tau1 table writes when their std < 3 %
P.est.lambdaD   = 0.999;                         % lag of the estimate location and excitation average (~100 s)
P.est.excMinD   = 0.01;                          % A^2, mean (0.1 s current change)^2 needed for table writes
P.est.lambda0   = 0.999;     % R0 forgetting factor, per 0.1 s sample (memory ~100 s)
P.est.lambdaRc  = 0.995;     % RC forgetting factor, per 1 s sample (memory ~200 s)
P.est.p0R0      = 1;         % initial R0 variance (Ohm^2)
P.est.p0Rc      = diag([100 1e-2 1e-2]);    % initial covariance of [a; c; d] (regressors y in V, i in A, 1)
P.est.pMaxR0    = 1;         % covariance caps (anti wind-up while not excited)
P.est.pMaxRc    = 1e4;   
P.est.infoR0    = 2e-3;      % R0 estimate used for the table when its RLS variance factor is below this
P.est.infoRc    = 2000;      % RC estimates used when P(1,1) (variance factor of a) is below this
P.est.lambdaExc = 0.98;      % excitation measure: average of (1 s mean current change)^2, memory ~50 s
P.est.excMin    = 0.05;      % A^2, RC tables are updated only above this (none during constant-current charge or rest)
P.est.rcIV      = true;      % instrumental variables for the RC branch (the blocks always use IV)
P.est.eta       = 2e-4;      % table step per 0.1 s at full weight, relative to the node value (x10 per RC update)
P.est.c0R0      = 2e4;       % R0 node step shrinks as c0/(c0 + weighted count) ...
P.est.c0Rc      = 2e3;       % ... same for R1 and tau1 (RC updates are 10x less frequent)
P.est.spread    = opts.Spread;   % spread learning to unvisited table points (see adaptiveEcm fill blocks)
P.est.cConfR0   = 2000;      % confidence of a node's own R0 data = count/(count + cConfR0)
P.est.cConfRc   = 200;       % same for R1, tau1 (RC updates are 10x less frequent)
lS = 1.5;  lT = 1.5;         % spreading kernel lengths, in table points
P.est.KS = exp(-abs((1:nS)' - (1:nS)) / lS);
P.est.KT = exp(-abs((1:nTe)' - (1:nTe)) / lT);
P.est.fillEps = 1e-6;
P.est.nearFrac  = 0.2;       % SOC nodes are moved only when the estimate lies within this fraction of the node spacing
P.est.stepFloor = 0.05;      % ... but not below this fraction (keeps tracking slow changes, e.g. ageing)
P.est.aMin      = exp(-P.TsRc / 5);     % bounds on a (tau1 in 5 .. 500 s)
P.est.aMax      = exp(-P.TsRc / 500);
P.est.ekfQ      = diag([1e-10 1e-7]);   % process noise [SOC; v1 (V^2)] per 0.1 s
P.est.ekfR      = (2e-3)^2;             % voltage measurement noise (V^2)
P.est.ekfP0     = diag([1e-4 1e-6]);
P.est.restI     = 0.05;      % A, |i| below this counts as rest
P.est.restT     = 1200;      % s, rest needed before an OCV reading for capacity
P.est.capMinDz  = 0.20;      % minimum SOC change between two rest readings
P.est.capW0     = 0.1;       % weight of the starting capacity, in SOC units
P.est.capLambda = 0.9;       % forgetting per capacity update
P.est.trendQ    = opts.TrendQ;   % capacity trend (alpha-beta on Q vs charge throughput)
P.est.trendAlpha = 0.7;      % level gain per capacity reading
P.est.trendBeta  = 0.2;      % slope gain per capacity reading
end

function C = loadCells(folder, seed, nominal)
if nargin < 3, nominal = false; end
old = cd(folder);  c = onCleanup(@() cd(old));
PLANT_variationSeed = seed; %#ok<NASGU>
if nominal
    evalc("bat_35E_13S7P_placeholder_params");
else
    evalc("bat_35E_13S7P_placeholder_params_hetero");
end
C.batMod = batMod;
if exist("PLANT_variation", "var"), C.PLANT_variation = PLANT_variation; else, C.PLANT_variation = []; end
end
