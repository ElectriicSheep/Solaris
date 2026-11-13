%% checkPlantFixedStep.m
% Accuracy of the fixed-step plant against a variable-step reference.
%
% The platform runs fixed-step (cfgHarness: ode1, 10 ms; Simscape local solver,
% backward Euler, fixed-cost iterations), as RT-LAB requires. This test checks that
% this costs no meaningful accuracy, by running bmsTestPlatform under a pulsed load:
%   reference : variable-step daessc (MaxStep hRef), global Simscape solve
%   fixed     : ode1 + local backward-Euler solver at each step size in Ts
% and comparing the true group voltages and cell temperatures from PLANT.
%
% Reports, per step size:
%   - max and RMS error in vGroup (mV) and tCell (K) against the reference
%   - execution wall time (initialisation excluded), time per step, and the
%     real-time factor (simulated time / wall time; > 1 is faster than real time)
% Desktop timing is an INDICATION only: the OP5033 core, its OS and RT-LAB's
% overheads differ, and real-time needs the worst-case step, not the average.
%
% Load edges: the reference is logged at most every hRef seconds, so interpolating it
% between logged points smears each instantaneous I*R0 voltage jump over the hRef
% before the edge. Samples from (edge - hRef) to (edge + Ts) are therefore excluded
% from the comparison; the number excluded is reported. The step instant itself is
% not checked.
%
% Pass criteria (provisional, chosen against the voltage sensor model):
%   max |dvGroup| < 1 mV  (2 x the 0.5 mV RMS sensor noise)
%   max |dtCell|  < 0.01 K (a tenth of the 0.1 K temperature LSB)
%
% Results depend on the cell parameters: re-run when the placeholder ECM values
% are replaced.
%
% Everything runs inside a function, so model callbacks that touch the base workspace
% cannot disturb the test's variables.
%
% Solver settings are changed only for these runs (configuration-reference overrides,
% restored on exit even after an error, and Simulink.SimulationInput block settings).
% Nothing is saved.
%
% Before running: vGroup, iPack and tCell in PLANT must be logged.

runCheck();

%% Local functions
function runCheck()
    mdl   = "bmsTestPlatform";
    tStop = 40;                  % s, two load pulses (four edges)
    Ts    = 0.01;                % s, platform step (add 0.1 to see the trend with step size)
    hRef  = 0.1;                 % s, reference MaxStep
    load_system(mdl);
    wasDirty = get_param(mdl, "Dirty");

    % Pulsed load: 1C for 10 s, rest 10 s; excites the fast voltage response
    base = Simulink.SimulationInput(mdl);
    base = base.setModelParameter("StopTime", num2str(tStop));
    base = base.setVariable("LOAD_profile", 2);
    base = base.setVariable("LOAD_pulsePeriod", 20);
    base = base.setVariable("LOAD_pulseDuty", 50);

    solverCfg = find_system(mdl, "MatchFilter", @Simulink.match.allVariants, ...
        "LookUnderMasks", "all", "FollowLinks", "on", ...
        "ReferenceBlock", "nesl_utility/Solver Configuration");
    assert(isscalar(solverCfg), "Expected one Solver Configuration block, found %d.", numel(solverCfg));
    solverCfg = solverCfg{1};

    assignin("base", "SENS_enableErrors", 0);   % read by sensor_params (ideal sensors)

    %% Reference run (variable step)
    outRef = simWithSolver(mdl, base, solverCfg, "variable", hRef, wasDirty);
    [tR, vR] = getLoggedSignal(outRef, "vGroup", "PLANT");
    [~,  TR] = getLoggedSignal(outRef, "tCell",  "PLANT");
    [tI, iR] = getLoggedSignal(outRef, "iPack",  "PLANT");
    tEdge   = tI(find(abs(diff(iR)) > 1) + 1);    % load steps (> 1 A change between logged points)
    wallRef = outRef.SimulationMetadata.TimingInfo.ExecutionElapsedWallTime;

    %% Fixed-step runs
    res = table('Size', [numel(Ts) 8], 'VariableTypes', repmat("double", 1, 8), ...
        'VariableNames', ["Ts_s","vMax_mV","vRMS_mV","tMax_K","excluded","wall_s","perStep_us","RTfactor"]);
    for k = 1:numel(Ts)
        out = simWithSolver(mdl, base, solverCfg, "fixed", Ts(k), wasDirty);
        [tF, vF] = getLoggedSignal(out, "vGroup", "PLANT");
        [~,  TF] = getLoggedSignal(out, "tCell",  "PLANT");

        keep = true(size(tF));
        for e = tEdge(:)'
            keep(tF > e - hRef & tF <= e + Ts(k)) = false;
        end
        dv = vF(keep,:) - interp1(tR, vR, tF(keep));
        dT = TF(keep,:) - interp1(tR, TR, tF(keep));
        wall = out.SimulationMetadata.TimingInfo.ExecutionElapsedWallTime;
        res(k,:) = {Ts(k), 1e3*max(abs(dv(:))), 1e3*sqrt(mean(dv(:).^2)), max(abs(dT(:))), ...
                    nnz(~keep), wall, 1e6*wall/(tStop/Ts(k)), tStop/wall};
    end
    evalin("base", "clear SENS_enableErrors");

    %% Report
    fprintf("\n=== Fixed-step plant vs variable-step reference, pulsed 1C load, %g s\n", tStop);
    fprintf("Reference (daessc, MaxStep %g s): execution %.2f s wall, real-time factor %.0f\n", ...
        hRef, wallRef, tStop/wallRef);
    fprintf("Load edges found: %d; samples from %.2f s before to one step after each edge excluded\n\n", ...
        numel(tEdge), hRef);
    disp(res)
    pass = res.vMax_mV < 1 & res.tMax_K < 0.01;
    for k = 1:numel(Ts)
        fprintf("Ts = %-6g accuracy %s\n", Ts(k), passFail(pass(k)));
    end
    fprintf("\nTiming is desktop wall time averaged over all steps; it is not a real-time guarantee.\n");
end

function out = simWithSolver(mdl, in, solverCfg, mode, h, wasDirty)
    % Runs one simulation with the requested solver; overrides are restored on exit.
    restore = onCleanup(@() restoreSolver(mdl, wasDirty)); %#ok<NASGU>
    if mode == "variable"
        setOverride(mdl, "SolverType", "Variable-step");
        setOverride(mdl, "SolverName", "daessc");
        setOverride(mdl, "MaxStep",    num2str(h));
        blk = ["UseLocalSolver", "off"];
    else
        setOverride(mdl, "SolverType", "Fixed-step");
        setOverride(mdl, "SolverName", "ode1");
        setOverride(mdl, "FixedStep",  num2str(h));
        blk = ["UseLocalSolver",        "on"
               "LocalSolverChoice",     "NE_BACKWARD_EULER_ADVANCER"
               "LocalSolverSampleTime", num2str(h)
               "DoFixedCost",           "on"
               "MaxNonlinIter",         "3"];
    end
    for j = 1:size(blk, 1)      % setBlockParameter takes one block/parameter/value per call
        in = in.setBlockParameter(solverCfg, blk(j,1), blk(j,2));
    end
    out = sim(in);
end

function setOverride(mdl, p, v)
    % Override a configuration-reference parameter only if it differs.
    if string(get_param(mdl, p)) ~= string(v)
        configset.reference.overrideParameter(mdl, p, v);
    end
end

function restoreSolver(mdl, wasDirty)
    over = configset.reference.getOverriddenParameters(mdl);
    for p = ["SolverType" "SolverName" "MaxStep" "FixedStep"]
        if any(over == p)
            configset.reference.restoreOverriddenParameter(mdl, p);
        end
    end
    set_param(mdl, "Dirty", wasDirty);
end

function s = passFail(ok)
    if ok, s = "PASS"; else, s = "FAIL"; end
end
