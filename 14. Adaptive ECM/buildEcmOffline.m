function buildEcmOffline()
%BUILDECMOFFLINE Builds ecmOffline.slx: fast group-level plant, load schedule,
% sensor model and the adaptive estimator (Subsystem Reference to adaptiveEcm.slx).
% Re-run to rebuild. Parameters come from the base-workspace struct ECM (ecmParams).

mdl = "ecmOffline";
here = fileparts(mfilename("fullpath"));
if bdIsLoaded(mdl), close_system(mdl, 0); end
f = fullfile(here, mdl + ".slx");
if isfile(f), delete(f); end
new_system(mdl);
set_param(mdl, "SolverType", "Variable-step", "Solver", "ode45", "RelTol", "1e-6", ...
    "AbsTol", "1e-8", "MaxStep", "ECM.Ts", "StopTime", "3600", ...
    "SaveOutput", "off", "SaveState", "off", "SaveTime", "off", "SignalLogging", "off", ...
    "ReturnWorkspaceOutputs", "on", "SaveFinalState", "off", ...
    "InitFcn", "if ~exist('ECM','var'), ECM = ecmParams; end", ...
    "AlgebraicLoopMsg", "error", "UnconnectedInputMsg", "error", "UnconnectedOutputMsg", "none");

%% LOAD
L = mdl + "/LOAD";
add_block("simulink/Ports & Subsystems/Subsystem", L, "Position", [60 60 220 180]);
delete_line(L, "In1/1", "Out1/1"); delete_block(L + "/In1"); delete_block(L + "/Out1");
inNames = ["zMin" "zMax" "vMax"];
for k = 1:3, add_block("simulink/Sources/In1", L + "/" + inNames(k), "Position", [20 40+60*k 50 54+60*k]); end
add_block("sflib/Chart", L + "/schedule", "Position", [200 60 380 300]);
consts = ["socLow" "ECM.load.socLow"; "socHigh" "ECM.load.socHigh"; "vLim" "ECM.load.vMax"; ...
          "tRest0" "ECM.load.tRest0"; "tRest" "ECM.load.tRest"];
for k = 1:size(consts, 1)
    add_block("simulink/Sources/Constant", L + "/" + consts(k,1), "Value", consts(k,2), ...
        "SampleTime", "inf", "Position", [60 260+40*k 140 280+40*k]);
end
buildScheduleChart(mdl, L + "/schedule");
for k = 1:3, add_line(L, inNames(k) + "/1", "schedule/" + k, "autorouting", "on"); end
for k = 1:size(consts, 1), add_line(L, consts(k,1) + "/1", "schedule/" + (k+3), "autorouting", "on"); end
add_block("simulink/Math Operations/Math Function", L + "/wrap", "Operator", "mod", "Position", [460 170 500 210]);
add_block("simulink/Sources/Constant", L + "/N", "Value", "ECM.load.N", "SampleTime", "inf", "Position", [400 220 440 240]);
add_block("simulink/Math Operations/Bias", L + "/kMinus1", "Bias", "-1", "Position", [410 160 440 190]);
add_block("simulink/Lookup Tables/Direct Lookup Table (n-D)", L + "/profile", "NumberOfTableDimensions", "1", ...
    "Table", "ECM.load.profile", "Position", [540 165 600 215]);
add_line(L, "schedule/2", "kMinus1/1", "autorouting", "on");
add_line(L, "kMinus1/1", "wrap/1", "autorouting", "on");
add_line(L, "N/1", "wrap/2", "autorouting", "on");
add_line(L, "wrap/1", "profile/1", "autorouting", "on");
add_block("simulink/Sources/Constant", L + "/zero", "Value", "0", "SampleTime", "inf", "Position", [540 60 570 80]);
add_block("simulink/Sources/Constant", L + "/iChg", "Value", "-ECM.load.iChg", "SampleTime", "inf", "Position", [540 250 600 270]);
add_block("simulink/Signal Routing/Multiport Switch", L + "/select", "Inputs", "5", ...
    "DataPortOrder", "Zero-based contiguous", "Position", [660 60 700 300]);
add_line(L, "schedule/1", "select/1", "autorouting", "on");
add_line(L, "zero/1", "select/2", "autorouting", "on");
add_line(L, "profile/1", "select/3", "autorouting", "on");
add_line(L, "zero/1", "select/4", "autorouting", "on");
add_line(L, "iChg/1", "select/5", "autorouting", "on");
add_line(L, "zero/1", "select/6", "autorouting", "on");
add_block("simulink/Sinks/Out1", L + "/i", "Position", [760 170 790 184]);
add_block("simulink/Sinks/Out1", L + "/mode", "Position", [760 230 790 244]);
add_line(L, "select/1", "i/1", "autorouting", "on");
add_line(L, "schedule/1", "mode/1", "autorouting", "on");

%% PLANT
Pp = mdl + "/PLANT";
add_block("simulink/Ports & Subsystems/Subsystem", Pp, "Position", [320 60 480 260]);
delete_line(Pp, "In1/1", "Out1/1"); delete_block(Pp + "/In1"); delete_block(Pp + "/Out1");
add_block("simulink/Sources/In1", Pp + "/i", "Position", [20 200 50 214]);
integ = ["Iz" "ECM.plant.soc0*ones(13,1)"; "Iv1" "zeros(13,1)"; "IT" "ECM.plant.T0C*ones(13,1)"; "IWh" "zeros(13,1)"];
for k = 1:4
    add_block("simulink/Continuous/Integrator", Pp + "/" + integ(k,1), "InitialCondition", integ(k,2), ...
        "Position", [900 40+120*(k-1) 940 80+120*(k-1)]);
end
add_block("simulink/Sources/Constant", Pp + "/gIdx", "Value", "(1:13)'", "SampleTime", "inf", "Position", [60 420 120 440]);
lut = ["ocv" "r0" "r1" "tau"];
for k = 1:4
    b = Pp + "/LUT_" + lut(k);
    add_block("simulink/Lookup Tables/n-D Lookup Table", b, "NumberOfTableDimensions", "3", ...
        "Position", [200 60+90*(k-1) 280 120+90*(k-1)]);
    set_param(b, "BreakpointsForDimension1", "ECM.plant.socBp", "BreakpointsForDimension2", "ECM.plant.tBpC", ...
        "BreakpointsForDimension3", "1:13", "Table", "ECM.plant." + lut(k), "ExtrapMethod", "Clip", ...
        "UseLastTableValue", "on");
    add_line(Pp, "Iz/1", "LUT_" + lut(k) + "/1", "autorouting", "on");
    add_line(Pp, "IT/1", "LUT_" + lut(k) + "/2", "autorouting", "on");
    add_line(Pp, "gIdx/1", "LUT_" + lut(k) + "/3", "autorouting", "on");
end
% dz = -i/(3600 Q)
add_block("simulink/Math Operations/Gain", Pp + "/kz", "Gain", "-1./(3600*ECM.plant.Q(:))", ...
    "Multiplication", "Element-wise(K.*u)", "Position", [700 40 760 80]);
add_line(Pp, "i/1", "kz/1", "autorouting", "on");  add_line(Pp, "kz/1", "Iz/1", "autorouting", "on");
% dv1 = (R1 i - v1)/tau
add_block("simulink/Math Operations/Product", Pp + "/R1i", "Inputs", "2", "Position", [400 150 430 190]);
add_block("simulink/Math Operations/Sum", Pp + "/sv1", "Inputs", "+-", "Position", [480 150 510 190]);
add_block("simulink/Math Operations/Product", Pp + "/dv1", "Inputs", "*/", "Position", [560 150 590 190]);
add_line(Pp, "LUT_r1/1", "R1i/1", "autorouting", "on"); add_line(Pp, "i/1", "R1i/2", "autorouting", "on");
add_line(Pp, "R1i/1", "sv1/1", "autorouting", "on"); add_line(Pp, "Iv1/1", "sv1/2", "autorouting", "on");
add_line(Pp, "sv1/1", "dv1/1", "autorouting", "on"); add_line(Pp, "LUT_tau/1", "dv1/2", "autorouting", "on");
add_line(Pp, "dv1/1", "Iv1/1", "autorouting", "on");
% v = ocv - v1 - R0 i
add_block("simulink/Math Operations/Product", Pp + "/R0i", "Inputs", "2", "Position", [400 250 430 290]);
add_block("simulink/Math Operations/Sum", Pp + "/sv", "Inputs", "+--", "Position", [480 230 510 290]);
add_line(Pp, "LUT_r0/1", "R0i/1", "autorouting", "on"); add_line(Pp, "i/1", "R0i/2", "autorouting", "on");
add_line(Pp, "LUT_ocv/1", "sv/1", "autorouting", "on"); add_line(Pp, "Iv1/1", "sv/2", "autorouting", "on");
add_line(Pp, "R0i/1", "sv/3", "autorouting", "on");
% dT = (i^2 R0 + v1^2/R1 - (T - Tamb)/Rth)/Cth
add_block("simulink/Math Operations/Product", Pp + "/q0", "Inputs", "***", "Position", [400 330 430 370]);
add_block("simulink/Math Operations/Product", Pp + "/q1", "Inputs", "**/", "Position", [400 390 430 430]);
add_block("simulink/Math Operations/Bias", Pp + "/dTa", "Bias", "-ECM.plant.tAmbC", "Position", [400 450 430 480]);
add_block("simulink/Math Operations/Gain", Pp + "/gRth", "Gain", "1./ECM.plant.Rth(:)", ...
    "Multiplication", "Element-wise(K.*u)", "Position", [460 450 520 480]);
add_block("simulink/Math Operations/Sum", Pp + "/sq", "Inputs", "++-", "Position", [560 340 590 480]);
add_block("simulink/Math Operations/Gain", Pp + "/gCth", "Gain", "1./ECM.plant.Cth(:)", ...
    "Multiplication", "Element-wise(K.*u)", "Position", [640 390 700 430]);
add_line(Pp, "i/1", "q0/1", "autorouting", "on"); add_line(Pp, "i/1", "q0/2", "autorouting", "on");
add_line(Pp, "LUT_r0/1", "q0/3", "autorouting", "on");
add_line(Pp, "Iv1/1", "q1/1", "autorouting", "on"); add_line(Pp, "Iv1/1", "q1/2", "autorouting", "on");
add_line(Pp, "LUT_r1/1", "q1/3", "autorouting", "on");
add_line(Pp, "IT/1", "dTa/1", "autorouting", "on"); add_line(Pp, "dTa/1", "gRth/1", "autorouting", "on");
add_line(Pp, "q0/1", "sq/1", "autorouting", "on"); add_line(Pp, "q1/1", "sq/2", "autorouting", "on");
add_line(Pp, "gRth/1", "sq/3", "autorouting", "on"); add_line(Pp, "sq/1", "gCth/1", "autorouting", "on");
add_line(Pp, "gCth/1", "IT/1", "autorouting", "on");
% Wh through each group (charge and discharge)
add_block("simulink/Math Operations/Product", Pp + "/p", "Inputs", "2", "Position", [640 500 670 540]);
add_block("simulink/Math Operations/Abs", Pp + "/absP", "Position", [700 505 730 535]);
add_block("simulink/Math Operations/Gain", Pp + "/toWh", "Gain", "1/3600", "Position", [760 505 800 535]);
add_line(Pp, "sv/1", "p/1", "autorouting", "on"); add_line(Pp, "i/1", "p/2", "autorouting", "on");
add_line(Pp, "p/1", "absP/1", "autorouting", "on"); add_line(Pp, "absP/1", "toWh/1", "autorouting", "on");
add_line(Pp, "toWh/1", "IWh/1", "autorouting", "on");
outs = ["v" "sv/1"; "z" "Iz/1"; "T" "IT/1"; "r0" "LUT_r0/1"; "r1" "LUT_r1/1"; "tau" "LUT_tau/1"; "Wh" "IWh/1"];
for k = 1:size(outs, 1)
    add_block("simulink/Sinks/Out1", Pp + "/" + outs(k,1), "Position", [1000 40+50*k 1030 54+50*k]);
    add_line(Pp, outs(k,2), outs(k,1) + "/1", "autorouting", "on");
end

%% SENSOR
S = mdl + "/SENSOR";
add_block("simulink/Ports & Subsystems/Subsystem", S, "Position", [600 60 760 220]);
delete_line(S, "In1/1", "Out1/1"); delete_block(S + "/In1"); delete_block(S + "/Out1");
sIn = ["v" "i" "T"];
for k = 1:3, add_block("simulink/Sources/In1", S + "/" + sIn(k), "Position", [20 60+120*(k-1) 50 74+120*(k-1)]); end
chan = [ ...
  "v" "13" "ECM.sens.vNoise" "0"                   "ECM.sens.vLsb" "vm"; ...
  "i" "1"  "ECM.sens.iNoise" "ECM.sens.iOffset"    "ECM.sens.iLsb" "im"; ...
  "T" "7"  "ECM.sens.tNoise" "0"                   "ECM.sens.tLsb" "Tth"];
for k = 1:3
    y = 40+120*(k-1); c = chan(k,1);
    add_block("simulink/Discrete/Zero-Order Hold", S + "/zoh_" + c, "SampleTime", "ECM.Ts", "Position", [100 y 130 y+30]);
    add_line(S, c + "/1", "zoh_" + c + "/1", "autorouting", "on");
    src = "zoh_" + c + "/1";
    if c == "T"
        add_block("simulink/Math Operations/Gain", S + "/thermMap", "Gain", "ECM.sens.thermMap", ...
            "Multiplication", "Matrix(K*u)", "Position", [160 y 210 y+30]);
        add_line(S, src, "thermMap/1", "autorouting", "on"); src = "thermMap/1";
    end
    add_block("simulink/Sources/Random Number", S + "/noise_" + c, "Mean", "zeros(" + chan(k,2) + ",1)", ...
        "Variance", chan(k,3) + "^2", "Seed", "ECM.sens.noiseSeed+" + k, "SampleTime", "ECM.Ts", "Position", [160 y+40 210 y+70]);
    add_block("simulink/Math Operations/Sum", S + "/add_" + c, "Inputs", "+++", "Position", [250 y 280 y+60]);
    add_block("simulink/Sources/Constant", S + "/offset_" + c, "Value", chan(k,4), "SampleTime", "inf", "Position", [160 y+80 210 y+100]);
    add_block("simulink/Discontinuities/Quantizer", S + "/q_" + c, "QuantizationInterval", chan(k,5), "Position", [320 y 360 y+30]);
    add_line(S, src, "add_" + c + "/1", "autorouting", "on");
    add_line(S, "noise_" + c + "/1", "add_" + c + "/2", "autorouting", "on");
    add_line(S, "offset_" + c + "/1", "add_" + c + "/3", "autorouting", "on");
    add_line(S, "add_" + c + "/1", "q_" + c + "/1", "autorouting", "on");
end
add_block("simulink/Signal Routing/Selector", S + "/perGroup", "NumberOfDimensions", "1", ...
    "IndexOptions", "Index vector (dialog)", "Indices", "ECM.sens.groupTherm", "InputPortWidth", "7", "Position", [400 280 440 310]);
add_line(S, "q_T/1", "perGroup/1", "autorouting", "on");
so = ["vm" "q_v/1"; "im" "q_i/1"; "Tg" "perGroup/1"; "Tth" "q_T/1"];
for k = 1:4
    add_block("simulink/Sinks/Out1", S + "/" + so(k,1), "Position", [500 40+60*k 530 54+60*k]);
    add_line(S, so(k,2), so(k,1) + "/1", "autorouting", "on");
end

%% Top-level wiring
add_line(mdl, "LOAD/1", "PLANT/1", "autorouting", "on");
add_line(mdl, "PLANT/1", "SENSOR/1", "autorouting", "on");
add_line(mdl, "LOAD/1", "SENSOR/2", "autorouting", "on");
add_line(mdl, "PLANT/3", "SENSOR/3", "autorouting", "on");
fb = ["zMin" "min" 2 1; "zMax" "max" 2 2; "vMax" "max" 1 3];
for k = 1:3
    add_block("simulink/Math Operations/MinMax", mdl + "/" + fb(k,1), "Function", fb(k,2), "Inputs", "1", ...
        "Position", [520 300+60*k 560 330+60*k]);
    add_block("simulink/Discrete/Unit Delay", mdl + "/d_" + fb(k,1), "SampleTime", "ECM.Ts", ...
        "InitialCondition", "0", "Position", [420 300+60*k 450 330+60*k]);
    add_line(mdl, "PLANT/" + fb(k,3), fb(k,1) + "/1", "autorouting", "on");
    add_line(mdl, fb(k,1) + "/1", "d_" + fb(k,1) + "/1", "autorouting", "on");
    add_line(mdl, "d_" + fb(k,1) + "/1", "LOAD/" + fb(k,4), "autorouting", "on");
end
set_param(mdl + "/d_zMin", "InitialCondition", "ECM.plant.soc0");
set_param(mdl + "/d_zMax", "InitialCondition", "ECM.plant.soc0");

%% Estimator
add_block("simulink/Ports & Subsystems/Subsystem Reference", mdl + "/EST", "ReferencedSubsystem", "adaptiveEcm", ...
    "Position", [880 60 1060 260]);
add_line(mdl, "SENSOR/1", "EST/1", "autorouting", "on");
add_line(mdl, "SENSOR/2", "EST/2", "autorouting", "on");
add_line(mdl, "SENSOR/3", "EST/3", "autorouting", "on");

%% Logging at ECM.TsLog (To Workspace, arrays)
logTruth = ["t_z" "PLANT/2"; "t_v" "PLANT/1"; "t_T" "PLANT/3"; "t_r0" "PLANT/4"; "t_r1" "PLANT/5"; ...
            "t_tau" "PLANT/6"; "t_Wh" "PLANT/7"; "t_i" "LOAD/1"; "t_mode" "LOAD/2"];
for k = 1:size(logTruth, 1), addLog(mdl, logTruth(k,1), logTruth(k,2), [300 400+40*k]); end
logEst = ["e_zh" "e_v1h" "e_r0" "e_r1" "e_tau" "e_Q" "e_r0Rls" "e_r1Rls" "e_tauRls"];
for k = 1:numel(logEst), addLog(mdl, logEst(k), "EST/" + k, [700 400+40*k]); end
% tables and counts: last value only
logTab = ["tabR0" "tabR1" "tabTau" "cntR0" "cntR1" "cntTau"];
for k = 1:numel(logTab)
    add_block("simulink/Sinks/To Workspace", mdl + "/" + logTab(k), "VariableName", logTab(k), ...
        "SaveFormat", "Structure With Time", "SampleTime", "ECM.TsLog", "MaxDataPoints", "1", ...
        "Position", [1500 400+40*k 1580 425+40*k]);
    add_line(mdl, "EST/" + (9+k), logTab(k) + "/1", "autorouting", "on");
end
% sensor signals at the sensor rate (for checking against the reference code);
% ECM.logSensorPoints = 1 keeps only the last sample
sens = ["s_vm" "SENSOR/1"; "s_im" "SENSOR/2"; "s_Tg" "SENSOR/3"];
for k = 1:3
    add_block("simulink/Sinks/To Workspace", mdl + "/" + sens(k,1), "VariableName", sens(k,1), ...
        "SaveFormat", "Array", "SampleTime", "ECM.Ts", "MaxDataPoints", "ECM.logSensorPoints", ...
        "Position", [1100 600+40*k 1180 625+40*k]);
    add_line(mdl, sens(k,2), sens(k,1) + "/1", "autorouting", "on");
end
save_system(mdl, f);
fprintf("Built %s\n", f);
end

function addLog(mdl, name, src, pos)
add_block("simulink/Sinks/To Workspace", mdl + "/" + name, "VariableName", name, "SaveFormat", "Array", ...
    "SampleTime", "ECM.TsLog", "MaxDataPoints", "inf", "Position", [pos(1)+700 pos(2) pos(1)+780 pos(2)+25]);
add_line(mdl, src, name + "/1", "autorouting", "on");
end

function buildScheduleChart(mdl, chartPath)
rt = sfroot;
ch = rt.find("-isa", "Stateflow.Chart", "Path", chartPath);
ch.ActionLanguage = "MATLAB";
ch.ChartUpdate = "DISCRETE";
ch.SampleTime = "ECM.Ts";
ins = ["zMin" "zMax" "vMax" "socLow" "socHigh" "vLim" "tRest0" "tRest"];
for k = 1:numel(ins)
    d = Stateflow.Data(ch); d.Name = ins(k); d.Scope = "Input"; d.Port = k;
end
outs = ["mode" "k"];
for k = 1:2
    d = Stateflow.Data(ch); d.Name = outs(k); d.Scope = "Output"; d.Port = k; d.Props.InitialValue = "0";
end
specs = { ...
  "REST0", "REST0" + newline + "entry: mode = 0;",                          [30 30 140 70]; ...
  "DIS",   "DIS" + newline + "entry: mode = 1; k = k + 1;" + newline + "during: k = k + 1;", [230 30 200 90]; ...
  "REST",  "REST" + newline + "entry: mode = 2;",                           [480 30 140 70]; ...
  "CHG",   "CHG" + newline + "entry: mode = 3;",                            [480 200 140 70]; ...
  "REST2", "REST2" + newline + "entry: mode = 4;",                          [230 200 140 70]};
S = containers.Map;
for k = 1:size(specs, 1)
    s = Stateflow.State(ch); s.LabelString = specs{k,2}; s.Position = specs{k,3}; S(specs{k,1}) = s;
end
t0 = Stateflow.Transition(ch); t0.Destination = S("REST0"); t0.DestinationOClock = 0;
t0.SourceEndpoint = t0.DestinationEndpoint - [0 30]; t0.Midpoint = t0.DestinationEndpoint - [0 15];
tr = ["REST0" "DIS"  "after(tRest0,sec)"; ...
      "DIS"   "REST" "[zMin <= socLow]"; ...
      "REST"  "CHG"  "after(tRest,sec)"; ...
      "CHG"   "REST2" "[zMax >= socHigh || vMax >= vLim]"; ...
      "REST2" "DIS"  "after(tRest,sec)"];
for k = 1:size(tr, 1)
    t = Stateflow.Transition(ch); t.Source = S(tr(k,1)); t.Destination = S(tr(k,2)); t.LabelString = tr(k,3);
end
end
