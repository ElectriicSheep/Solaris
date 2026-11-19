function buildAdaptiveEcm()
%BUILDADAPTIVEECM Builds adaptiveEcm.slx (a subsystem file) from Simulink blocks.
%
% One For Each iteration per parallel group (13). Per group, at ECM.Ts (0.1 s):
%   opPoint   R0, R1, tau1 from the group's SOC x temperature tables
%   ekf       SOC and RC voltage, 2-state EKF using the table values and capacity
%   r0Rls     R0 by forgetting-factor RLS on voltage and current differences
%   r0Table   moves the R0 table towards the RLS estimate (median-type sign step)
%   rcRls     every ECM.TsRc (1 s): R1 and tau1 by instrumental-variable FFRLS on
%             the RC voltage y = OCV(SOC) - v - R0*i, then moves the R1 and tau1 tables
%   capacity  charge between two rested OCV readings / SOC change between them
% Tables, counts and all estimator states are Unit Delays. See README.md.
%
% Re-run to rebuild. Parameters come from the base-workspace struct ECM (ecmParams).

mdl = "adaptiveEcm";
here = fileparts(mfilename("fullpath"));
if bdIsLoaded(mdl), close_system(mdl, 0); end
f = fullfile(here, mdl + ".slx");
if isfile(f), delete(f); end
new_system(mdl, "Subsystem");

in = ["vm" "im" "Tg"];
for k = 1:3, B(mdl, in(k), "In"); end
G = mdl + "/group";
add_block("simulink/Ports & Subsystems/For Each Subsystem", G);
delete_line(G, "In1/1", "Out1/1"); delete_block(G + "/In1"); delete_block(G + "/Out1");
fe = G + "/For Each";

% --- mask parameters (initial values, partitioned per group) ---
m = Simulink.Mask.create(G);
mp = ["r0Init" "ECM.est.init.r0" "3"; "r1Init" "ECM.est.init.r1" "3"; "tauInit" "ECM.est.init.tau" "3"; ...
      "c0Init" "ECM.est.init.count(:,:,:,1)" "3"; "c1Init" "ECM.est.init.count(:,:,:,2)" "3"; ...
      "c2Init" "ECM.est.init.count(:,:,:,3)" "3"; "QInit" "ECM.est.init.Q" "2"; ...
      "th0Init" "ECM.est.init.th0" "2"; "thRcInit" "ECM.est.init.thRc" "2"];
for k = 1:size(mp, 1)
    m.addParameter("Name", mp(k,1), "Prompt", mp(k,1), "Value", mp(k,2), "Type", "edit");
end
set_param(fe, "SubsysMaskParameterPartition", cellstr(repmat("on", 1, size(mp,1))), ...
    "SubsysMaskParameterPartitionDimension", cellstr(mp(:,3)'), ...
    "SubsysMaskParameterPartitionWidth", cellstr(repmat("1", 1, size(mp,1))));

for k = 1:3, B(G, in(k), "In"); end
set_param(fe, "InputPartition", {'on','off','on'}, "InputPartitionDimension", {'1','1','1'}, ...
    "InputPartitionWidth", {'1','1','1'});

buildGroup(G);
% Inport dimensions everywhere inside the group (tables 11 x 6, all else scalar), so
% the feedback loops through the table memories have defined sizes
ip = find_system(G, "LookUnderMasks", "all", "FollowLinks", "on", "BlockType", "Inport");
for k = 1:numel(ip)
    nmI = string(get_param(ip{k}, "Name"));
    if startsWith(nmI, ["tab" "cnt"])
        set_param(ip{k}, "PortDimensions", "[numel(ECM.est.socBp) numel(ECM.est.tBpC)]");
    else
        set_param(ip{k}, "PortDimensions", "1");
    end
end

outs = ["zh" 1; "v1h" 1; "r0" 1; "r1" 1; "tau" 1; "Q" 1; "r0Rls" 1; "r1Rls" 1; "tauRls" 1; ...
        "tabR0" 3; "tabR1" 3; "tabTau" 3; "cntR0" 3; "cntR1" 3; "cntTau" 3];
for k = 1:size(outs, 1)
    B(mdl, outs(k,1), "Out");
    add_line(mdl, "group/" + k, outs(k,1) + "/1", "autorouting", "smart");
end
set_param(fe, "OutputConcatenationDimension", cellstr(outs(:,2)'));
for k = 1:3, add_line(mdl, in(k) + "/1", "group/" + k, "autorouting", "smart"); end
arrange(mdl);
save_system(mdl, f);
fprintf("Built %s\n", f);
end

%% ===================================================================== group
function buildGroup(G)
% Inports vm, im, Tg (scalars per iteration). Outports in the order of buildAdaptiveEcm.
B(G, "iPrev", "UD", "InitialCondition", "0", "SampleTime", "ECM.Ts");
B(G, "vPrev", "UD", "InitialCondition", "0", "SampleTime", "ECM.Ts");
C(G, "im/1", "iPrev/1"); C(G, "vm/1", "vPrev/1");
B(G, "first", "UD", "InitialCondition", "1", "SampleTime", "ECM.Ts");
B(G, "zero", "Const", "Value", "0");
C(G, "zero/1", "first/1");

% tables (states)
tabs = ["tabR0" "r0Init"; "tabR1" "r1Init"; "tabTau" "tauInit"; "cntR0" "c0Init"; "cntR1" "c1Init"; "cntTau" "c2Init"];
for k = 1:size(tabs, 1)
    B(G, tabs(k,1) + "Mem", "UD", "InitialCondition", tabs(k,2), "SampleTime", "ECM.Ts");
    B(G, "upd_" + tabs(k,1), "Sum", "Inputs", "++");
    C(G, tabs(k,1) + "Mem/1", "upd_" + tabs(k,1) + "/1");
    C(G, "upd_" + tabs(k,1) + "/1", tabs(k,1) + "Mem/1");
end

% tables as read: unvisited points take their visited neighbours' correction ratio
fills = ["tabR0" "cntR0" "r0Init" "ECM.est.cConfR0"; "tabR1" "cntR1" "r1Init" "ECM.est.cConfRc"; ...
         "tabTau" "cntTau" "tauInit" "ECM.est.cConfRc"];
for k = 1:3
    S = subsys(G, "fill_" + fills(k,1), ["tab" "cnt"], "used");
    buildFill(S, fills(k,3), fills(k,4));
    C(G, fills(k,1) + "Mem/1", "fill_" + fills(k,1) + "/1");
    C(G, fills(k,2) + "Mem/1", "fill_" + fills(k,1) + "/2");
end

% capacity (gives the capacity used this step, from the previous step's sums)
S = subsys(G, "capacity", ["v" "i" "iAvg"], ["Qprev" "Q"]);
buildCapacity(S);
C(G, "vm/1", "capacity/1"); C(G, "im/1", "capacity/2");

% EKF (contains the SOC state; outputs zhPrev for the table lookup)
S = subsys(G, "ekf", ["v" "i" "iPrev" "first" "R0" "R1" "tau" "Q"], ["zh" "v1h" "zhPrev"]);
buildEkf(S);
C(G, "vm/1", "ekf/1"); C(G, "im/1", "ekf/2"); C(G, "iPrev/1", "ekf/3"); C(G, "first/1", "ekf/4");
C(G, "capacity/1", "ekf/8");

% operating point from the tables at the previous SOC estimate
S = subsys(G, "opPoint", ["z" "T" "tabR0" "tabR1" "tabTau"], ["R0" "R1" "tau"]);
buildOpPoint(S);
C(G, "ekf/3", "opPoint/1"); C(G, "Tg/1", "opPoint/2");
C(G, "fill_tabR0/1", "opPoint/3"); C(G, "fill_tabR1/1", "opPoint/4"); C(G, "fill_tabTau/1", "opPoint/5");
C(G, "opPoint/1", "ekf/5"); C(G, "opPoint/2", "ekf/6"); C(G, "opPoint/3", "ekf/7");

% R0 RLS and table
S = subsys(G, "r0Ident", ["v" "vPrev" "i" "iPrev" "first"], ["R0" "informed"]);
buildR0Rls(S);
C(G, "vm/1", "r0Ident/1"); C(G, "vPrev/1", "r0Ident/2"); C(G, "im/1", "r0Ident/3"); C(G, "iPrev/1", "r0Ident/4");
C(G, "first/1", "r0Ident/5");
S = subsys(G, "r0Table", ["theta" "enable" "z" "T" "first" "tab" "cnt"], ["dTab" "dCnt"]);
buildLaggedTableUpdate(S, "ECM.est.lambda0", "ECM.est.eta", "ECM.est.c0R0");
C(G, "cntR0Mem/1", "r0Table/7");
C(G, "r0Ident/1", "r0Table/1"); C(G, "r0Ident/2", "r0Table/2"); C(G, "ekf/1", "r0Table/3");
C(G, "Tg/1", "r0Table/4"); C(G, "first/1", "r0Table/5"); C(G, "fill_tabR0/1", "r0Table/6");
C(G, "r0Table/1", "upd_tabR0/2"); C(G, "r0Table/2", "upd_cntR0/2");

% RC branch: y = OCV(zh) - v - R0*i, identified every ECM.TsRc
B(G, "ocv", "LUT1", "BreakpointsForDimension1", "ECM.est.socBp", "Table", "ECM.est.ocv", "ExtrapMethod", "Clip", "UseLastTableValue", "on");
B(G, "R0i", "Prod", "Inputs", "2");
B(G, "y", "Sum", "Inputs", "+--");
C(G, "ekf/1", "ocv/1"); C(G, "opPoint/1", "R0i/1"); C(G, "im/1", "R0i/2");
C(G, "ocv/1", "y/1"); C(G, "vm/1", "y/2"); C(G, "R0i/1", "y/3");
B(G, "iWin", "FIR", "Coefficients", "ones(1,round(ECM.TsRc/ECM.Ts))/round(ECM.TsRc/ECM.Ts)", "SampleTime", "ECM.Ts");
C(G, "iPrev/1", "iWin/1"); C(G, "iWin/1", "capacity/3");
% tick: every round(TsRc/Ts) steps (steps 10, 20, ...)
B(G, "count", "UD", "InitialCondition", "0", "SampleTime", "ECM.Ts");
B(G, "countInc", "Bias", "Bias", "1");
B(G, "countWrap", "Math", "Operator", "mod");
B(G, "nDec", "Const", "Value", "round(ECM.TsRc/ECM.Ts)");
B(G, "nDec1", "Const", "Value", "round(ECM.TsRc/ECM.Ts)-1");
B(G, "tick", "Rel", "Operator", "==");
C(G, "count/1", "countInc/1"); C(G, "countInc/1", "countWrap/1"); C(G, "nDec/1", "countWrap/2");
C(G, "countWrap/1", "count/1"); C(G, "count/1", "tick/1"); C(G, "nDec1/1", "tick/2");
S = mdlEnabled(G, "rcIdent", ["y" "iWin" "R1" "tau" "z" "T" "tabR1" "tabTau" "cntR1" "cntTau"], ...
    ["dR1" "dTau" "dC1" "dC2" "R1rls" "tauRls"]);
buildRcRls(S);
for nmIn = ["tabR1" "tabTau" "cntR1" "cntTau"]
    set_param(S + "/" + nmIn, "PortDimensions", "[numel(ECM.est.socBp) numel(ECM.est.tBpC)]");
end
C(G, "y/1", "rcIdent/1"); C(G, "iWin/1", "rcIdent/2"); C(G, "opPoint/2", "rcIdent/3"); C(G, "opPoint/3", "rcIdent/4");
C(G, "ekf/1", "rcIdent/5"); C(G, "Tg/1", "rcIdent/6"); C(G, "fill_tabR1/1", "rcIdent/7"); C(G, "fill_tabTau/1", "rcIdent/8");
C(G, "cntR1Mem/1", "rcIdent/9"); C(G, "cntTauMem/1", "rcIdent/10");
C(G, "tick/1", "rcIdent/Enable");
C(G, "rcIdent/1", "upd_tabR1/2"); C(G, "rcIdent/2", "upd_tabTau/2");
C(G, "rcIdent/3", "upd_cntR1/2"); C(G, "rcIdent/4", "upd_cntTau/2");

% outports
outs = ["zh" "ekf/1"; "v1h" "ekf/2"; "r0" "opPoint/1"; "r1" "opPoint/2"; "tau" "opPoint/3"; ...
        "Q" "capacity/2"; "r0Rls" "r0Ident/1"; "r1Rls" "rcIdent/5"; "tauRls" "rcIdent/6"; ...
        "tabR0" "fill_tabR0/1"; "tabR1" "fill_tabR1/1"; "tabTau" "fill_tabTau/1"; ...
        "cntR0" "upd_cntR0/1"; "cntR1" "upd_cntR1/1"; "cntTau" "upd_cntTau/1"];
for k = 1:size(outs, 1)
    B(G, outs(k,1), "Out");
    C(G, outs(k,2), outs(k,1) + "/1");
end
arrange(G);
end

%% ===================================================================== fill
function buildFill(S, initName, cConf)
% Correction ratio R = table / starting table. Confidence of a point's own data:
% conf = count/(count + cConf). Ratio from the neighbours (kernel KS over SOC, KT over T):
%   Rfill = (KS*(conf.*R)*KT' + eps) ./ (KS*conf*KT' + eps)    (-> 1 with no data nearby)
% Table as read: start .* (conf.*R + (1-conf).*Rfill). Learning (the stored table) is unchanged.
% ECM.est.spread = 0 passes the stored table through.
dims = "[numel(ECM.est.socBp) numel(ECM.est.tBpC)]";
set_param(S + "/tab", "PortDimensions", dims); set_param(S + "/cnt", "PortDimensions", dims);
B(S, "init", "Const", "Value", initName);
B(S, "R", "Prod", "Inputs", "*/"); C(S, "tab/1", "R/1"); C(S, "init/1", "R/2");
B(S, "cConf", "Const", "Value", cConf);
B(S, "cntC", "Sum", "Inputs", "++"); C(S, "cnt/1", "cntC/1"); C(S, "cConf/1", "cntC/2");
B(S, "conf", "Prod", "Inputs", "*/"); C(S, "cnt/1", "conf/1"); C(S, "cntC/1", "conf/2");
B(S, "A", "Prod", "Inputs", "2"); C(S, "conf/1", "A/1"); C(S, "R/1", "A/2");
B(S, "KS", "Const", "Value", "ECM.est.KS"); B(S, "KTt", "Const", "Value", "ECM.est.KT'");
B(S, "num", "Prod", "Inputs", "3", "Multiplication", "Matrix(*)"); C(S, "KS/1", "num/1"); C(S, "A/1", "num/2"); C(S, "KTt/1", "num/3");
B(S, "den", "Prod", "Inputs", "3", "Multiplication", "Matrix(*)"); C(S, "KS/1", "den/1"); C(S, "conf/1", "den/2"); C(S, "KTt/1", "den/3");
B(S, "numE", "Bias", "Bias", "ECM.est.fillEps"); C(S, "num/1", "numE/1");
B(S, "denE", "Bias", "Bias", "ECM.est.fillEps"); C(S, "den/1", "denE/1");
B(S, "Rfill", "Prod", "Inputs", "*/"); C(S, "numE/1", "Rfill/1"); C(S, "denE/1", "Rfill/2");
B(S, "nconf", "Gain", "Gain", "-1"); C(S, "conf/1", "nconf/1");
B(S, "omc", "Bias", "Bias", "1"); C(S, "nconf/1", "omc/1");
B(S, "B2", "Prod", "Inputs", "2"); C(S, "omc/1", "B2/1"); C(S, "Rfill/1", "B2/2");
B(S, "Rused", "Sum", "Inputs", "++"); C(S, "A/1", "Rused/1"); C(S, "B2/1", "Rused/2");
B(S, "filled", "Prod", "Inputs", "2"); C(S, "init/1", "filled/1"); C(S, "Rused/1", "filled/2");
B(S, "spread", "Const", "Value", "double(ECM.est.spread)");
B(S, "sel", "Switch", "Criteria", "u2 ~= 0"); C(S, "filled/1", "sel/1"); C(S, "spread/1", "sel/2"); C(S, "tab/1", "sel/3");
C(S, "sel/1", "used/1");
arrange(S);
end

%% ===================================================================== EKF
function buildEkf(S)
% States zh, v1h, P (p11 p12 p22). First step: zh = OCV^-1(v), v1h = 0.
B(S, "ocvInv", "LUT1", "BreakpointsForDimension1", "ECM.est.ocv", "Table", "ECM.est.socBp", "ExtrapMethod", "Clip", "UseLastTableValue", "on");
C(S, "v/1", "ocvInv/1");
B(S, "zMem", "UD", "InitialCondition", "0", "SampleTime", "ECM.Ts");
B(S, "v1Mem", "UD", "InitialCondition", "0", "SampleTime", "ECM.Ts");
B(S, "p11Mem", "UD", "InitialCondition", "ECM.est.ekfP0(1,1)", "SampleTime", "ECM.Ts");
B(S, "p12Mem", "UD", "InitialCondition", "ECM.est.ekfP0(1,2)", "SampleTime", "ECM.Ts");
B(S, "p22Mem", "UD", "InitialCondition", "ECM.est.ekfP0(2,2)", "SampleTime", "ECM.Ts");
B(S, "zPrevSel", "Switch", "Criteria", "u2 > Threshold", "Threshold", "0.5");
C(S, "ocvInv/1", "zPrevSel/1"); C(S, "first/1", "zPrevSel/2"); C(S, "zMem/1", "zPrevSel/3");
B(S, "zeroV1", "Const", "Value", "0");
B(S, "v1PrevSel", "Switch", "Criteria", "u2 > Threshold", "Threshold", "0.5");
C(S, "zeroV1/1", "v1PrevSel/1"); C(S, "first/1", "v1PrevSel/2"); C(S, "v1Mem/1", "v1PrevSel/3");
C(S, "zPrevSel/1", "zhPrev/1");
% a = exp(-Ts/tau)
B(S, "TsOverTau", "Prod", "Inputs", "*/");
B(S, "Ts", "Const", "Value", "-ECM.Ts");
C(S, "Ts/1", "TsOverTau/1"); C(S, "tau/1", "TsOverTau/2");
B(S, "a", "Math", "Operator", "exp"); C(S, "TsOverTau/1", "a/1");
% zp = zPrev - Ts*iPrev/(3600 Q)
B(S, "iOverQ", "Prod", "Inputs", "*/"); C(S, "iPrev/1", "iOverQ/1"); C(S, "Q/1", "iOverQ/2");
B(S, "kz", "Gain", "Gain", "ECM.Ts/3600"); C(S, "iOverQ/1", "kz/1");
B(S, "zp", "Sum", "Inputs", "+-"); C(S, "zPrevSel/1", "zp/1"); C(S, "kz/1", "zp/2");
% v1p = a v1Prev + R1 (1-a) iPrev
B(S, "aV1", "Prod", "Inputs", "2"); C(S, "a/1", "aV1/1"); C(S, "v1PrevSel/1", "aV1/2");
B(S, "oneMinusA", "Bias", "Bias", "1"); B(S, "negA", "Gain", "Gain", "-1");
C(S, "a/1", "negA/1"); C(S, "negA/1", "oneMinusA/1");
B(S, "drive", "Prod", "Inputs", "3"); C(S, "R1/1", "drive/1"); C(S, "oneMinusA/1", "drive/2"); C(S, "iPrev/1", "drive/3");
B(S, "v1p", "Sum", "Inputs", "++"); C(S, "aV1/1", "v1p/1"); C(S, "drive/1", "v1p/2");
% covariance prediction
B(S, "p11p", "Bias", "Bias", "ECM.est.ekfQ(1,1)"); C(S, "p11Mem/1", "p11p/1");
B(S, "p12p", "Prod", "Inputs", "2"); C(S, "a/1", "p12p/1"); C(S, "p12Mem/1", "p12p/2");
B(S, "a2p22", "Prod", "Inputs", "3"); C(S, "a/1", "a2p22/1"); C(S, "a/1", "a2p22/2"); C(S, "p22Mem/1", "a2p22/3");
B(S, "p22p", "Bias", "Bias", "ECM.est.ekfQ(2,2)"); C(S, "a2p22/1", "p22p/1");
% measurement: vhat = OCV(zp) - v1p - R0 i,  h = dOCV/dz at zp
B(S, "ocv", "LUT1", "BreakpointsForDimension1", "ECM.est.socBp", "Table", "ECM.est.ocv", "ExtrapMethod", "Clip", "UseLastTableValue", "on");
B(S, "h", "LUT1", "BreakpointsForDimension1", "ECM.est.socBp(1:end-1)", "Table", "diff(ECM.est.ocv)./diff(ECM.est.socBp)", ...
    "InterpMethod", "Flat", "ExtrapMethod", "Clip", "UseLastTableValue", "on");
C(S, "zp/1", "ocv/1"); C(S, "zp/1", "h/1");
B(S, "R0i", "Prod", "Inputs", "2"); C(S, "R0/1", "R0i/1"); C(S, "i/1", "R0i/2");
B(S, "vhat", "Sum", "Inputs", "+--"); C(S, "ocv/1", "vhat/1"); C(S, "v1p/1", "vhat/2"); C(S, "R0i/1", "vhat/3");
B(S, "inn", "Sum", "Inputs", "+-"); C(S, "v/1", "inn/1"); C(S, "vhat/1", "inn/2");
% g1 = h p11 - p12 ; g2 = h p12 - p22 ; S = h g1 - g2 + R
B(S, "hp11", "Prod", "Inputs", "2"); C(S, "h/1", "hp11/1"); C(S, "p11p/1", "hp11/2");
B(S, "g1", "Sum", "Inputs", "+-"); C(S, "hp11/1", "g1/1"); C(S, "p12p/1", "g1/2");
B(S, "hp12", "Prod", "Inputs", "2"); C(S, "h/1", "hp12/1"); C(S, "p12p/1", "hp12/2");
B(S, "g2", "Sum", "Inputs", "+-"); C(S, "hp12/1", "g2/1"); C(S, "p22p/1", "g2/2");
B(S, "hg1", "Prod", "Inputs", "2"); C(S, "h/1", "hg1/1"); C(S, "g1/1", "hg1/2");
B(S, "Sinn", "Sum", "Inputs", "+-"); C(S, "hg1/1", "Sinn/1"); C(S, "g2/1", "Sinn/2");
B(S, "Sv", "Bias", "Bias", "ECM.est.ekfR"); C(S, "Sinn/1", "Sv/1");
B(S, "K1", "Prod", "Inputs", "*/"); C(S, "g1/1", "K1/1"); C(S, "Sv/1", "K1/2");
B(S, "K2", "Prod", "Inputs", "*/"); C(S, "g2/1", "K2/1"); C(S, "Sv/1", "K2/2");
% state update
B(S, "K1inn", "Prod", "Inputs", "2"); C(S, "K1/1", "K1inn/1"); C(S, "inn/1", "K1inn/2");
B(S, "zSum", "Sum", "Inputs", "++"); C(S, "zp/1", "zSum/1"); C(S, "K1inn/1", "zSum/2");
B(S, "zSat", "Sat", "UpperLimit", "1", "LowerLimit", "0"); C(S, "zSum/1", "zSat/1");
B(S, "K2inn", "Prod", "Inputs", "2"); C(S, "K2/1", "K2inn/1"); C(S, "inn/1", "K2inn/2");
B(S, "v1Sum", "Sum", "Inputs", "++"); C(S, "v1p/1", "v1Sum/1"); C(S, "K2inn/1", "v1Sum/2");
C(S, "zSat/1", "zMem/1"); C(S, "v1Sum/1", "v1Mem/1");
C(S, "zSat/1", "zh/1"); C(S, "v1Sum/1", "v1h/1");
% covariance update
B(S, "K1g1", "Prod", "Inputs", "2"); C(S, "K1/1", "K1g1/1"); C(S, "g1/1", "K1g1/2");
B(S, "p11n", "Sum", "Inputs", "+-"); C(S, "p11p/1", "p11n/1"); C(S, "K1g1/1", "p11n/2");
B(S, "K1g2", "Prod", "Inputs", "2"); C(S, "K1/1", "K1g2/1"); C(S, "g2/1", "K1g2/2");
B(S, "p12n", "Sum", "Inputs", "+-"); C(S, "p12p/1", "p12n/1"); C(S, "K1g2/1", "p12n/2");
B(S, "K2g2", "Prod", "Inputs", "2"); C(S, "K2/1", "K2g2/1"); C(S, "g2/1", "K2g2/2");
B(S, "p22n", "Sum", "Inputs", "+-"); C(S, "p22p/1", "p22n/1"); C(S, "K2g2/1", "p22n/2");
C(S, "p11n/1", "p11Mem/1"); C(S, "p12n/1", "p12Mem/1"); C(S, "p22n/1", "p22Mem/1");
arrange(S);
end

%% ===================================================================== op point
function buildOpPoint(S)
B(S, "preZ", "Pre", "BreakpointsData", "ECM.est.socBp", "ExtrapMethod", "Clip");
B(S, "preT", "Pre", "BreakpointsData", "ECM.est.tBpC", "ExtrapMethod", "Clip");
C(S, "z/1", "preZ/1"); C(S, "T/1", "preT/1");
nm = ["R0" "R1" "tau"]; tn = ["tabR0" "tabR1" "tabTau"];
for k = 1:3
    b = "interp" + nm(k);
    B(S, b, "Interp", "NumberOfTableDimensions", "2", "TableSource", "Input port");
    C(S, "preZ/1", b + "/1"); C(S, "preZ/2", b + "/2"); C(S, "preT/1", b + "/3"); C(S, "preT/2", b + "/4");
    C(S, tn(k) + "/1", b + "/5");
    C(S, b + "/1", nm(k) + "/1");
end
arrange(S);
end

%% ===================================================================== R0 RLS
function buildR0Rls(S)
% dv = -R0 di (+ small terms), scalar FFRLS:  phi = -di
B(S, "dv", "Sum", "Inputs", "+-"); C(S, "v/1", "dv/1"); C(S, "vPrev/1", "dv/2");
B(S, "di", "Sum", "Inputs", "+-"); C(S, "i/1", "di/1"); C(S, "iPrev/1", "di/2");
B(S, "phi", "Gain", "Gain", "-1"); C(S, "di/1", "phi/1");
% first step: phi = 0 (no update)
B(S, "zeroPhi", "Const", "Value", "0");
B(S, "phiSel", "Switch", "Criteria", "u2 > Threshold", "Threshold", "0.5");
C(S, "zeroPhi/1", "phiSel/1"); C(S, "first/1", "phiSel/2"); C(S, "phi/1", "phiSel/3");
B(S, "thMem", "UD", "InitialCondition", "th0Init", "SampleTime", "ECM.Ts");
B(S, "pMem", "UD", "InitialCondition", "ECM.est.p0R0", "SampleTime", "ECM.Ts");
B(S, "pPhi", "Prod", "Inputs", "2"); C(S, "pMem/1", "pPhi/1"); C(S, "phiSel/1", "pPhi/2");
B(S, "phiPphi", "Prod", "Inputs", "2"); C(S, "pPhi/1", "phiPphi/1"); C(S, "phiSel/1", "phiPphi/2");
B(S, "den", "Bias", "Bias", "ECM.est.lambda0"); C(S, "phiPphi/1", "den/1");
B(S, "K", "Prod", "Inputs", "*/"); C(S, "pPhi/1", "K/1"); C(S, "den/1", "K/2");
B(S, "phiTh", "Prod", "Inputs", "2"); C(S, "phiSel/1", "phiTh/1"); C(S, "thMem/1", "phiTh/2");
B(S, "e", "Sum", "Inputs", "+-"); C(S, "dv/1", "e/1"); C(S, "phiTh/1", "e/2");
B(S, "Ke", "Prod", "Inputs", "2"); C(S, "K/1", "Ke/1"); C(S, "e/1", "Ke/2");
B(S, "th", "Sum", "Inputs", "++"); C(S, "thMem/1", "th/1"); C(S, "Ke/1", "th/2");
C(S, "th/1", "thMem/1");
B(S, "KphiP", "Prod", "Inputs", "2"); C(S, "K/1", "KphiP/1"); C(S, "pPhi/1", "KphiP/2");
B(S, "pNum", "Sum", "Inputs", "+-"); C(S, "pMem/1", "pNum/1"); C(S, "KphiP/1", "pNum/2");
B(S, "pDiv", "Gain", "Gain", "1/ECM.est.lambda0"); C(S, "pNum/1", "pDiv/1");
B(S, "pCap", "MinMax", "Function", "min", "Inputs", "2");
B(S, "pMax", "Const", "Value", "ECM.est.pMaxR0");
C(S, "pDiv/1", "pCap/1"); C(S, "pMax/1", "pCap/2"); C(S, "pCap/1", "pMem/1");
B(S, "info", "Const", "Value", "ECM.est.infoR0");
B(S, "inf", "Rel", "Operator", "<"); C(S, "pCap/1", "inf/1"); C(S, "info/1", "inf/2");
C(S, "th/1", "R0/1"); C(S, "inf/1", "informed/1");
arrange(S);
end

%% ===================================================================== table update
function buildLaggedTableUpdate(S, lambda, eta, c0)
% Location of the estimate: exponential average of SOC and T with the same
% forgetting factor as the RLS (the estimate is a weighted average over that window).
lag = ["z" "zLag"; "T" "TLag"];
for k = 1:2
    nm = lag(k,2);
    B(S, nm + "Mem", "UD", "InitialCondition", "0", "SampleTime", "-1");
    B(S, nm + "Old", "Switch", "Criteria", "u2 > Threshold", "Threshold", "0.5");
    C(S, lag(k,1) + "/1", nm + "Old/1"); C(S, "first/1", nm + "Old/2"); C(S, nm + "Mem/1", nm + "Old/3");
    B(S, nm + "A", "Gain", "Gain", lambda); C(S, nm + "Old/1", nm + "A/1");
    B(S, nm + "B", "Gain", "Gain", "1-" + lambda); C(S, lag(k,1) + "/1", nm + "B/1");
    B(S, nm, "Sum", "Inputs", "++"); C(S, nm + "A/1", nm + "/1"); C(S, nm + "B/1", nm + "/2");
    C(S, nm + "/1", nm + "Mem/1");
end
S2 = subsys(S, "nodeUpdate", ["theta" "enable" "z" "T" "tab" "cnt"], ["dTab" "dCnt"]);
buildNodeUpdate(S2, eta, c0);
C(S, "cnt/1", "nodeUpdate/6");
C(S, "theta/1", "nodeUpdate/1"); C(S, "enable/1", "nodeUpdate/2");
C(S, "zLag/1", "nodeUpdate/3"); C(S, "TLag/1", "nodeUpdate/4"); C(S, "tab/1", "nodeUpdate/5");
C(S, "nodeUpdate/1", "dTab/1"); C(S, "nodeUpdate/2", "dCnt/1");
arrange(S);
end

function buildNodeUpdate(S, eta, c0)
% e = theta - table(z,T); the 4 surrounding nodes move by eta*w*node*sign(e).
B(S, "preZ", "Pre", "BreakpointsData", "ECM.est.socBp", "ExtrapMethod", "Clip");
B(S, "preT", "Pre", "BreakpointsData", "ECM.est.tBpC", "ExtrapMethod", "Clip");
C(S, "z/1", "preZ/1"); C(S, "T/1", "preT/1");
B(S, "interp", "Interp", "NumberOfTableDimensions", "2", "TableSource", "Input port");
C(S, "preZ/1", "interp/1"); C(S, "preZ/2", "interp/2"); C(S, "preT/1", "interp/3"); C(S, "preT/2", "interp/4");
C(S, "tab/1", "interp/5");
B(S, "e", "Sum", "Inputs", "+-"); C(S, "theta/1", "e/1"); C(S, "interp/1", "e/2");
B(S, "sgn", "Sign"); C(S, "e/1", "sgn/1");
% weights: ws (nS x 1), wt (nT x 1), W = ws * wt'
ax = ["S" "preZ" "(0:numel(ECM.est.socBp)-1)'"; "T" "preT" "(0:numel(ECM.est.tBpC)-1)'"];
for k = 1:2
    a = ax(k,1);
    B(S, "idx" + a, "Const", "Value", ax(k,3));
    B(S, "k" + a, "Conv", "OutDataTypeStr", "double"); C(S, ax(k,2) + "/1", "k" + a + "/1");
    B(S, "k" + a + "1", "Bias", "Bias", "1"); C(S, "k" + a + "/1", "k" + a + "1/1");
    B(S, "lo" + a, "Rel", "Operator", "=="); C(S, "idx" + a + "/1", "lo" + a + "/1"); C(S, "k" + a + "/1", "lo" + a + "/2");
    B(S, "hi" + a, "Rel", "Operator", "=="); C(S, "idx" + a + "/1", "hi" + a + "/1"); C(S, "k" + a + "1/1", "hi" + a + "/2");
    B(S, "loD" + a, "Conv", "OutDataTypeStr", "double"); C(S, "lo" + a + "/1", "loD" + a + "/1");
    B(S, "hiD" + a, "Conv", "OutDataTypeStr", "double"); C(S, "hi" + a + "/1", "hiD" + a + "/1");
    B(S, "f" + a, "Conv", "OutDataTypeStr", "double"); C(S, ax(k,2) + "/2", "f" + a + "/1");
    B(S, "omf" + a, "Bias", "Bias", "1"); B(S, "nf" + a, "Gain", "Gain", "-1");
    C(S, "f" + a + "/1", "nf" + a + "/1"); C(S, "nf" + a + "/1", "omf" + a + "/1");
    if a == "S"
        % SOC axis: only the node the estimate lies close to is moved (within
        % ECM.est.nearFrac of the node spacing), with weight 1. Moving both
        % neighbours of a point between nodes leaves a zig-zag in the table when
        % the operating point sweeps one way (discharge).
        B(S, "nearLo", "Const", "Value", "ECM.est.nearFrac");
        B(S, "nearHi", "Const", "Value", "1-ECM.est.nearFrac");
        B(S, "isLo", "Rel", "Operator", "<="); C(S, "fS/1", "isLo/1"); C(S, "nearLo/1", "isLo/2");
        B(S, "isHi", "Rel", "Operator", ">="); C(S, "fS/1", "isHi/1"); C(S, "nearHi/1", "isHi/2");
        B(S, "isLoD", "Conv", "OutDataTypeStr", "double"); C(S, "isLo/1", "isLoD/1");
        B(S, "isHiD", "Conv", "OutDataTypeStr", "double"); C(S, "isHi/1", "isHiD/1");
        B(S, "wLoS", "Prod", "Inputs", "2"); C(S, "loDS/1", "wLoS/1"); C(S, "isLoD/1", "wLoS/2");
        B(S, "wHiS", "Prod", "Inputs", "2"); C(S, "hiDS/1", "wHiS/1"); C(S, "isHiD/1", "wHiS/2");
    else
    B(S, "wLo" + a, "Prod", "Inputs", "2"); C(S, "loD" + a + "/1", "wLo" + a + "/1"); C(S, "omf" + a + "/1", "wLo" + a + "/2");
    B(S, "wHi" + a, "Prod", "Inputs", "2"); C(S, "hiD" + a + "/1", "wHi" + a + "/1"); C(S, "f" + a + "/1", "wHi" + a + "/2");
    end
    B(S, "w" + a, "Sum", "Inputs", "++"); C(S, "wLo" + a + "/1", "w" + a + "/1"); C(S, "wHi" + a + "/1", "w" + a + "/2");
end
B(S, "wTt", "Math", "Operator", "transpose"); C(S, "wT/1", "wTt/1");
B(S, "W", "Prod", "Inputs", "2", "Multiplication", "Matrix(*)"); C(S, "wS/1", "W/1"); C(S, "wTt/1", "W/2");
% when not enabled the increments are exactly zero (a Switch, so a non-finite
% estimate cannot reach the table through 0*NaN)
B(S, "zeros", "Const", "Value", "zeros(numel(ECM.est.socBp), numel(ECM.est.tBpC))");
B(S, "cntInc", "Switch", "Criteria", "u2 ~= 0"); C(S, "W/1", "cntInc/1"); C(S, "enable/1", "cntInc/2"); C(S, "zeros/1", "cntInc/3");
C(S, "cntInc/1", "dCnt/1");
B(S, "stepRaw", "Prod", "Inputs", "4"); C(S, "W/1", "stepRaw/1");
B(S, "step", "Switch", "Criteria", "u2 ~= 0"); C(S, "stepRaw/1", "step/1"); C(S, "enable/1", "step/2"); C(S, "zeros/1", "step/3"); C(S, "tab/1", "stepRaw/2"); C(S, "sgn/1", "stepRaw/3");
B(S, "eta", "Const", "Value", eta);
% step shrinks as a node collects updates: eta * max(c0/(c0 + count), floor)
B(S, "c0", "Const", "Value", c0);
B(S, "c0n", "Sum", "Inputs", "++"); C(S, "c0/1", "c0n/1"); C(S, "cnt/1", "c0n/2");
B(S, "shrink", "Prod", "Inputs", "*/"); C(S, "c0/1", "shrink/1"); C(S, "c0n/1", "shrink/2");
B(S, "floor", "Const", "Value", "ECM.est.stepFloor");
B(S, "shrinkF", "MinMax", "Function", "max", "Inputs", "2"); C(S, "shrink/1", "shrinkF/1"); C(S, "floor/1", "shrinkF/2");
B(S, "etaN", "Prod", "Inputs", "2"); C(S, "eta/1", "etaN/1"); C(S, "shrinkF/1", "etaN/2");
C(S, "etaN/1", "stepRaw/4");
C(S, "step/1", "dTab/1");
arrange(S);
end

%% ===================================================================== RC RLS
function buildRcRls(S)
% Runs only on ticks (Enabled Subsystem). Delays here advance once per tick.
% theta = [a; c; d]:  y_n = a y_{n-1} + c iWin_n + d,  R1 = c/(1-a), tau1 = -TsRc/ln(a)
% Instrument for y_{n-1}: auxiliary model output from the table R1, tau1 (noise free).
B(S, "has", "UD", "InitialCondition", "0", "SampleTime", "-1");
B(S, "one", "Const", "Value", "1");
C(S, "one/1", "has/1");
B(S, "yPrev", "UD", "InitialCondition", "0", "SampleTime", "-1"); C(S, "y/1", "yPrev/1");
B(S, "xPrev", "UD", "InitialCondition", "0", "SampleTime", "-1");
% auxiliary model
B(S, "TsOverTau", "Prod", "Inputs", "*/"); B(S, "mTs", "Const", "Value", "-ECM.TsRc");
C(S, "mTs/1", "TsOverTau/1"); C(S, "tau/1", "TsOverTau/2");
B(S, "aa", "Math", "Operator", "exp"); C(S, "TsOverTau/1", "aa/1");
B(S, "naa", "Gain", "Gain", "-1"); B(S, "omaa", "Bias", "Bias", "1"); C(S, "aa/1", "naa/1"); C(S, "naa/1", "omaa/1");
B(S, "ax", "Prod", "Inputs", "2"); C(S, "aa/1", "ax/1"); C(S, "xPrev/1", "ax/2");
B(S, "bx", "Prod", "Inputs", "3"); C(S, "R1/1", "bx/1"); C(S, "omaa/1", "bx/2"); C(S, "iWin/1", "bx/3");
B(S, "x", "Sum", "Inputs", "++"); C(S, "ax/1", "x/1"); C(S, "bx/1", "x/2"); C(S, "x/1", "xPrev/1");
% regressor and instrument
B(S, "phi", "Concat", "NumInputs", "3", "Mode", "Multidimensional array", "ConcatenateDimension", "1"); C(S, "yPrev/1", "phi/1"); C(S, "iWin/1", "phi/2"); C(S, "one/1", "phi/3");
B(S, "zeta", "Concat", "NumInputs", "3", "Mode", "Multidimensional array", "ConcatenateDimension", "1"); C(S, "xPrev/1", "zeta/1"); C(S, "iWin/1", "zeta/2"); C(S, "one/1", "zeta/3");
B(S, "thMem", "UD", "InitialCondition", "thRcInit", "SampleTime", "-1");
B(S, "PMem", "UD", "InitialCondition", "ECM.est.p0Rc", "SampleTime", "-1");
B(S, "Pz", "Prod", "Inputs", "2", "Multiplication", "Matrix(*)"); C(S, "PMem/1", "Pz/1"); C(S, "zeta/1", "Pz/2");
B(S, "phiT", "Math", "Operator", "transpose"); C(S, "phi/1", "phiT/1");
B(S, "phiPz", "Prod", "Inputs", "2", "Multiplication", "Matrix(*)"); C(S, "phiT/1", "phiPz/1"); C(S, "Pz/1", "phiPz/2");
B(S, "den", "Bias", "Bias", "ECM.est.lambdaRc"); C(S, "phiPz/1", "den/1");
B(S, "K", "Prod", "Inputs", "*/"); C(S, "Pz/1", "K/1"); C(S, "den/1", "K/2");
B(S, "yhat", "Prod", "Inputs", "2", "Multiplication", "Matrix(*)"); C(S, "phiT/1", "yhat/1"); C(S, "thMem/1", "yhat/2");
B(S, "e", "Sum", "Inputs", "+-"); C(S, "y/1", "e/1"); C(S, "yhat/1", "e/2");
B(S, "Ke", "Prod", "Inputs", "2"); C(S, "K/1", "Ke/1"); C(S, "e/1", "Ke/2");
% update only after the first tick and when the IV denominator is safely positive
B(S, "denMin", "Const", "Value", "0.5*ECM.est.lambdaRc");
B(S, "denOk", "Rel", "Operator", ">"); C(S, "den/1", "denOk/1"); C(S, "denMin/1", "denOk/2");
B(S, "hasL", "Rel", "Operator", ">"); B(S, "zeroH", "Const", "Value", "0"); C(S, "has/1", "hasL/1"); C(S, "zeroH/1", "hasL/2");
B(S, "upd", "Logic", "Operator", "AND", "Inputs", "2"); C(S, "hasL/1", "upd/1"); C(S, "denOk/1", "upd/2");
B(S, "hasD", "Conv", "OutDataTypeStr", "double"); C(S, "upd/1", "hasD/1");
B(S, "KeOn", "Prod", "Inputs", "2"); C(S, "Ke/1", "KeOn/1"); C(S, "hasD/1", "KeOn/2");
B(S, "thTry", "Sum", "Inputs", "++"); C(S, "thMem/1", "thTry/1"); C(S, "KeOn/1", "thTry/2");
B(S, "absTh", "Abs"); C(S, "thTry/1", "absTh/1");
B(S, "thLim", "Const", "Value", "1e3");
B(S, "thSmall", "Rel", "Operator", "<"); C(S, "absTh/1", "thSmall/1"); C(S, "thLim/1", "thSmall/2");
B(S, "thFinite", "Logic", "Operator", "AND", "Inputs", "1"); C(S, "thSmall/1", "thFinite/1");
B(S, "th", "Switch", "Criteria", "u2 ~= 0"); C(S, "thTry/1", "th/1"); C(S, "thFinite/1", "th/2"); C(S, "thMem/1", "th/3");
C(S, "th/1", "thMem/1");
B(S, "phiTP", "Prod", "Inputs", "2", "Multiplication", "Matrix(*)"); C(S, "phiT/1", "phiTP/1"); C(S, "PMem/1", "phiTP/2");
B(S, "KphiTP", "Prod", "Inputs", "2", "Multiplication", "Matrix(*)"); C(S, "K/1", "KphiTP/1"); C(S, "phiTP/1", "KphiTP/2");
B(S, "KphiTPon", "Prod", "Inputs", "2"); C(S, "KphiTP/1", "KphiTPon/1"); C(S, "hasD/1", "KphiTPon/2");
B(S, "Pnum", "Sum", "Inputs", "+-"); C(S, "PMem/1", "Pnum/1"); C(S, "KphiTPon/1", "Pnum/2");
% divide by lambda only when updating
B(S, "lamInv", "Const", "Value", "1/ECM.est.lambdaRc");
B(S, "scaleL", "Switch", "Criteria", "u2 > Threshold", "Threshold", "0.5");
C(S, "lamInv/1", "scaleL/1"); C(S, "hasD/1", "scaleL/2"); C(S, "one/1", "scaleL/3");
B(S, "Pl", "Prod", "Inputs", "2"); C(S, "Pnum/1", "Pl/1"); C(S, "scaleL/1", "Pl/2");
% trace cap
B(S, "eye3", "Const", "Value", "eye(3)");
B(S, "diagP", "Prod", "Inputs", "2"); C(S, "Pl/1", "diagP/1"); C(S, "eye3/1", "diagP/2");
B(S, "tr", "Sum", "Inputs", "+", "CollapseMode", "All dimensions"); C(S, "diagP/1", "tr/1");
B(S, "pMax", "Const", "Value", "ECM.est.pMaxRc");
B(S, "ratio", "Prod", "Inputs", "*/"); C(S, "pMax/1", "ratio/1"); C(S, "tr/1", "ratio/2");
B(S, "sc", "MinMax", "Function", "min", "Inputs", "2"); C(S, "ratio/1", "sc/1"); C(S, "one/1", "sc/2");
B(S, "PnTry", "Prod", "Inputs", "2"); C(S, "Pl/1", "PnTry/1"); C(S, "sc/1", "PnTry/2");
B(S, "P0", "Const", "Value", "ECM.est.p0Rc");
B(S, "Pn", "Switch", "Criteria", "u2 ~= 0"); C(S, "PnTry/1", "Pn/1"); C(S, "thFinite/1", "Pn/2"); C(S, "P0/1", "Pn/3");
C(S, "Pn/1", "PMem/1");
% parameters
B(S, "selA", "Selector", "NumberOfDimensions", "1", "IndexOptions", "Index vector (dialog)", "Indices", "1", "InputPortWidth", "3");
B(S, "selC", "Selector", "NumberOfDimensions", "1", "IndexOptions", "Index vector (dialog)", "Indices", "2", "InputPortWidth", "3");
C(S, "th/1", "selA/1"); C(S, "th/1", "selC/1");
B(S, "aSat", "Sat", "UpperLimit", "ECM.est.aMax", "LowerLimit", "ECM.est.aMin"); C(S, "selA/1", "aSat/1");
B(S, "na", "Gain", "Gain", "-1"); B(S, "oma", "Bias", "Bias", "1"); C(S, "aSat/1", "na/1"); C(S, "na/1", "oma/1");
B(S, "R1e", "Prod", "Inputs", "*/"); C(S, "selC/1", "R1e/1"); C(S, "oma/1", "R1e/2");
B(S, "lna", "Math", "Operator", "log"); C(S, "aSat/1", "lna/1");
B(S, "tauE", "Prod", "Inputs", "*/"); C(S, "mTs/1", "tauE/1"); C(S, "lna/1", "tauE/2");
C(S, "R1e/1", "R1rls/1"); C(S, "tauE/1", "tauRls/1");
% informed: P(1,1) < info, a inside its bounds, R1 > 0, not the first tick
B(S, "e1", "Const", "Value", "[1;0;0]", "VectorParams1D", "off"); B(S, "e1T", "Const", "Value", "[1 0 0]", "VectorParams1D", "off");
B(S, "Pe1", "Prod", "Inputs", "2", "Multiplication", "Matrix(*)"); C(S, "Pn/1", "Pe1/1"); C(S, "e1/1", "Pe1/2");
B(S, "selP11", "Prod", "Inputs", "2", "Multiplication", "Matrix(*)"); C(S, "e1T/1", "selP11/1"); C(S, "Pe1/1", "selP11/2");
B(S, "info", "Const", "Value", "ECM.est.infoRc");
B(S, "c1", "Rel", "Operator", "<"); C(S, "selP11/1", "c1/1"); C(S, "info/1", "c1/2");
B(S, "aMin", "Const", "Value", "ECM.est.aMin"); B(S, "aMax", "Const", "Value", "ECM.est.aMax");
B(S, "c2", "Rel", "Operator", ">"); C(S, "selA/1", "c2/1"); C(S, "aMin/1", "c2/2");
B(S, "c3", "Rel", "Operator", "<"); C(S, "selA/1", "c3/1"); C(S, "aMax/1", "c3/2");
B(S, "zeroR", "Const", "Value", "0");
B(S, "c4", "Rel", "Operator", ">"); C(S, "R1e/1", "c4/1"); C(S, "zeroR/1", "c4/2");
B(S, "hasB", "Logic", "Operator", "AND", "Inputs", "2"); C(S, "hasL/1", "hasB/1"); C(S, "thFinite/1", "hasB/2");
% excitation: average of (change of the 1 s mean current)^2; none during rest or constant-current charge
B(S, "iWinPrev", "UD", "InitialCondition", "0", "SampleTime", "-1"); C(S, "iWin/1", "iWinPrev/1");
B(S, "dI", "Sum", "Inputs", "+-"); C(S, "iWin/1", "dI/1"); C(S, "iWinPrev/1", "dI/2");
B(S, "dI2", "Prod", "Inputs", "2"); C(S, "dI/1", "dI2/1"); C(S, "dI/1", "dI2/2");
B(S, "excMem", "UD", "InitialCondition", "0", "SampleTime", "-1");
B(S, "excA", "Gain", "Gain", "ECM.est.lambdaExc"); C(S, "excMem/1", "excA/1");
B(S, "excB", "Gain", "Gain", "1-ECM.est.lambdaExc"); C(S, "dI2/1", "excB/1");
B(S, "exc", "Sum", "Inputs", "++"); C(S, "excA/1", "exc/1"); C(S, "excB/1", "exc/2"); C(S, "exc/1", "excMem/1");
B(S, "excMin", "Const", "Value", "ECM.est.excMin");
B(S, "c5", "Rel", "Operator", ">="); C(S, "exc/1", "c5/1"); C(S, "excMin/1", "c5/2");
B(S, "ok", "Logic", "Operator", "AND", "Inputs", "6");
C(S, "c1/1", "ok/1"); C(S, "c2/1", "ok/2"); C(S, "c3/1", "ok/3"); C(S, "c4/1", "ok/4"); C(S, "hasB/1", "ok/5"); C(S, "c5/1", "ok/6");
% first tick flag for the lag filters
B(S, "firstTick", "Logic", "Operator", "NOT"); C(S, "hasL/1", "firstTick/1");
B(S, "ftD", "Conv", "OutDataTypeStr", "double"); C(S, "firstTick/1", "ftD/1");
% table updates (step per tick = eta * ticks per second-equivalent)
U = subsys(S, "r1Table", ["theta" "enable" "z" "T" "first" "tab" "cnt"], ["dTab" "dCnt"]);
buildLaggedTableUpdate(U, "ECM.est.lambdaRc", "ECM.est.eta*round(ECM.TsRc/ECM.Ts)", "ECM.est.c0Rc");
U = subsys(S, "tauTable", ["theta" "enable" "z" "T" "first" "tab" "cnt"], ["dTab" "dCnt"]);
buildLaggedTableUpdate(U, "ECM.est.lambdaRc", "ECM.est.eta*round(ECM.TsRc/ECM.Ts)", "ECM.est.c0Rc");
C(S, "cntR1/1", "r1Table/7"); C(S, "cntTau/1", "tauTable/7");
C(S, "R1e/1", "r1Table/1"); C(S, "ok/1", "r1Table/2"); C(S, "z/1", "r1Table/3"); C(S, "T/1", "r1Table/4");
C(S, "ftD/1", "r1Table/5"); C(S, "tabR1/1", "r1Table/6");
C(S, "tauE/1", "tauTable/1"); C(S, "ok/1", "tauTable/2"); C(S, "z/1", "tauTable/3"); C(S, "T/1", "tauTable/4");
C(S, "ftD/1", "tauTable/5"); C(S, "tabTau/1", "tauTable/6");
C(S, "r1Table/1", "dR1/1"); C(S, "tauTable/1", "dTau/1"); C(S, "r1Table/2", "dC1/1"); C(S, "tauTable/2", "dC2/1");
% increments are zero between ticks; estimates hold
for o = ["dR1" "dTau" "dC1" "dC2"]
    set_param(S + "/" + o, "OutputWhenDisabled", "reset", "InitialOutput", "0");
end
for o = ["R1rls" "tauRls"]
    set_param(S + "/" + o, "OutputWhenDisabled", "held", "InitialOutput", "0");
end
arrange(S);
end

%% ===================================================================== capacity
function buildCapacity(S)
% Rest: |i| < restI for restT. At each rest: zO = OCV^-1(v). Between two rests with
% |dz| >= capMinDz:  S1 = lam*S1 + |Ah|, S2 = lam*S2 + |dz|,  Q = S1/S2.
B(S, "S1Mem", "UD", "InitialCondition", "ECM.est.capW0*QInit", "SampleTime", "ECM.Ts");
B(S, "S2Mem", "UD", "InitialCondition", "ECM.est.capW0", "SampleTime", "ECM.Ts");
B(S, "Qprev_", "Prod", "Inputs", "*/"); C(S, "S1Mem/1", "Qprev_/1"); C(S, "S2Mem/1", "Qprev_/2");
C(S, "Qprev_/1", "Qprev/1");
% charge since the last rest reading
B(S, "AhMem", "UD", "InitialCondition", "0", "SampleTime", "ECM.Ts");
B(S, "dAh", "Gain", "Gain", "ECM.Ts/3600"); C(S, "i/1", "dAh/1");
B(S, "Ah", "Sum", "Inputs", "++"); C(S, "AhMem/1", "Ah/1"); C(S, "dAh/1", "Ah/2");
% rest timer
B(S, "absI", "Abs"); C(S, "iAvg/1", "absI/1");   % 1 s mean current (less sensitive to noise)
B(S, "restI", "Const", "Value", "ECM.est.restI");
B(S, "isRest", "Rel", "Operator", "<"); C(S, "absI/1", "isRest/1"); C(S, "restI/1", "isRest/2");
B(S, "tMem", "UD", "InitialCondition", "0", "SampleTime", "ECM.Ts");
B(S, "tInc", "Bias", "Bias", "ECM.Ts"); C(S, "tMem/1", "tInc/1");
B(S, "zeroT", "Const", "Value", "0");
B(S, "tRest", "Switch", "Criteria", "u2 ~= 0"); C(S, "tInc/1", "tRest/1"); C(S, "isRest/1", "tRest/2"); C(S, "zeroT/1", "tRest/3");
C(S, "tRest/1", "tMem/1");
B(S, "restT", "Const", "Value", "ECM.est.restT");
B(S, "nowRested", "Rel", "Operator", ">="); C(S, "tRest/1", "nowRested/1"); C(S, "restT/1", "nowRested/2");
B(S, "wasRested", "Rel", "Operator", ">="); C(S, "tMem/1", "wasRested/1"); C(S, "restT/1", "wasRested/2");
B(S, "notWas", "Logic", "Operator", "NOT"); C(S, "wasRested/1", "notWas/1");
B(S, "event", "Logic", "Operator", "AND", "Inputs", "2"); C(S, "nowRested/1", "event/1"); C(S, "notWas/1", "event/2");
% OCV reading and previous one
B(S, "ocvInv", "LUT1", "BreakpointsForDimension1", "ECM.est.ocv", "Table", "ECM.est.socBp", "ExtrapMethod", "Clip", "UseLastTableValue", "on");
C(S, "v/1", "ocvInv/1");
B(S, "zRMem", "UD", "InitialCondition", "0", "SampleTime", "ECM.Ts");
B(S, "zR", "Switch", "Criteria", "u2 ~= 0"); C(S, "ocvInv/1", "zR/1"); C(S, "event/1", "zR/2"); C(S, "zRMem/1", "zR/3");
C(S, "zR/1", "zRMem/1");
B(S, "haveMem", "UD", "InitialCondition", "0", "SampleTime", "ECM.Ts");
B(S, "have", "Logic", "Operator", "OR", "Inputs", "2"); C(S, "haveMem/1", "have/1"); C(S, "event/1", "have/2");
B(S, "haveD", "Conv", "OutDataTypeStr", "double"); C(S, "have/1", "haveD/1"); C(S, "haveD/1", "haveMem/1");
B(S, "dz", "Sum", "Inputs", "+-"); C(S, "zRMem/1", "dz/1"); C(S, "ocvInv/1", "dz/2");
B(S, "absDz", "Abs"); C(S, "dz/1", "absDz/1");
B(S, "minDz", "Const", "Value", "ECM.est.capMinDz");
B(S, "bigDz", "Rel", "Operator", ">="); C(S, "absDz/1", "bigDz/1"); C(S, "minDz/1", "bigDz/2");
B(S, "hadB", "Rel", "Operator", ">"); B(S, "zeroH", "Const", "Value", "0");
C(S, "haveMem/1", "hadB/1"); C(S, "zeroH/1", "hadB/2");
B(S, "use", "Logic", "Operator", "AND", "Inputs", "3"); C(S, "event/1", "use/1"); C(S, "hadB/1", "use/2"); C(S, "bigDz/1", "use/3");
B(S, "absAh", "Abs"); C(S, "Ah/1", "absAh/1");
B(S, "lS1", "Gain", "Gain", "ECM.est.capLambda"); C(S, "S1Mem/1", "lS1/1");
B(S, "S1n", "Sum", "Inputs", "++"); C(S, "lS1/1", "S1n/1"); C(S, "absAh/1", "S1n/2");
B(S, "S1", "Switch", "Criteria", "u2 ~= 0"); C(S, "S1n/1", "S1/1"); C(S, "use/1", "S1/2"); C(S, "S1Mem/1", "S1/3");
B(S, "lS2", "Gain", "Gain", "ECM.est.capLambda"); C(S, "S2Mem/1", "lS2/1");
B(S, "S2n", "Sum", "Inputs", "++"); C(S, "lS2/1", "S2n/1"); C(S, "absDz/1", "S2n/2");
B(S, "S2", "Switch", "Criteria", "u2 ~= 0"); C(S, "S2n/1", "S2/1"); C(S, "use/1", "S2/2"); C(S, "S2Mem/1", "S2/3");
C(S, "S1/1", "S1Mem/1"); C(S, "S2/1", "S2Mem/1");
B(S, "Qn", "Prod", "Inputs", "*/"); C(S, "S1/1", "Qn/1"); C(S, "S2/1", "Qn/2"); C(S, "Qn/1", "Q/1");
% reset the charge counter at each rest reading
B(S, "AhNext", "Switch", "Criteria", "u2 ~= 0"); C(S, "zeroT/1", "AhNext/1"); C(S, "event/1", "AhNext/2"); C(S, "Ah/1", "AhNext/3");
C(S, "AhNext/1", "AhMem/1");
arrange(S);
end

%% ===================================================================== helpers
function S = subsys(P, name, ins, outs)
S = P + "/" + name;
add_block("simulink/Ports & Subsystems/Subsystem", S);
delete_line(S, "In1/1", "Out1/1"); delete_block(S + "/In1"); delete_block(S + "/Out1");
for k = 1:numel(ins), B(S, ins(k), "In"); end
for k = 1:numel(outs), B(S, outs(k), "Out"); end
end

function S = mdlEnabled(P, name, ins, outs)
S = P + "/" + name;
add_block("simulink/Ports & Subsystems/Enabled Subsystem", S);
delete_line(S, "In1/1", "Out1/1"); delete_block(S + "/In1"); delete_block(S + "/Out1");
for k = 1:numel(ins), B(S, ins(k), "In"); end
for k = 1:numel(outs), B(S, outs(k), "Out"); end
end

function B(sys, name, type, varargin)
lib = struct("In", "simulink/Sources/In1", "Out", "simulink/Sinks/Out1", ...
    "Const", "simulink/Sources/Constant", "Gain", "simulink/Math Operations/Gain", ...
    "Sum", "simulink/Math Operations/Sum", "Prod", "simulink/Math Operations/Product", ...
    "Math", "simulink/Math Operations/Math Function", "UD", "simulink/Discrete/Unit Delay", ...
    "Sat", "simulink/Discontinuities/Saturation", "Sign", "simulink/Math Operations/Sign", ...
    "Rel", "simulink/Logic and Bit Operations/Relational Operator", ...
    "Logic", "simulink/Logic and Bit Operations/Logical Operator", ...
    "Switch", "simulink/Signal Routing/Switch", "Conv", "simulink/Signal Attributes/Data Type Conversion", ...
    "LUT1", "simulink/Lookup Tables/1-D Lookup Table", "Pre", "simulink/Lookup Tables/Prelookup", ...
    "Interp", "simulink/Lookup Tables/Interpolation Using Prelookup", ...
    "MinMax", "simulink/Math Operations/MinMax", "Abs", "simulink/Math Operations/Abs", ...
    "FIR", "simulink/Discrete/Discrete FIR Filter", "Bias", "simulink/Math Operations/Bias", ...
    "Selector", "simulink/Signal Routing/Selector", "Concat", "simulink/Math Operations/Vector Concatenate");
add_block(lib.(type), sys + "/" + name, varargin{:});
end

function C(sys, src, dst)
add_line(sys, src, dst, "autorouting", "smart");
end

function arrange(sys)
try, Simulink.BlockDiagram.arrangeSystem(sys); catch, end
end
