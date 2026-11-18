function annotateBMS(mdl)
%ANNOTATEBMS Write the documentation note inside each BMS layer of bms.slx.
%   annotateBMS() regenerates one note per layer (MEAS, PLAUS, BMSVL, SOA, DIAG, SE, BMS),
%   placed above the layer's blocks. Bus elements (name, size, unit, description) and
%   parameter values are read from bms.sldd (and the contract it references), so after
%   changing a bus or a parameter, run annotateBMS again and the notes match.
%   Each note lists: the layer's purpose, the acronyms it uses, every element of each
%   input and output bus ("*" = used by this layer), the parameters with their current
%   values, what the layer does, and its current limitations.
%   The model is left open and modified, not saved.

    arguments
        mdl (1,1) string = "bms"
    end
    load_system(mdl);
    sec = getSection(Simulink.data.dictionary.open(get_param(mdl, "DataDictionary")), "Design Data");

    G = glossary();
    for L = addPwr(addLog(layers()))
        sys = mdl + "/" + L.name;
        lines = [L.title; ""; "ACRONYMS"; "  " + G(L.acr(:)); ""];
        for k = 1:size(L.ins, 1)
            lines = [lines; busLines(sec, "IN ", L.ins{k,1}, L.ins{k,2}, L.ins{k,3}); ""]; %#ok<AGROW>
        end
        if ~isempty(L.params)
            lines = [lines; "PARAMETERS (bms.sldd)"]; %#ok<AGROW>
            for p = L.params, lines = [lines; paramLines(sec, p)]; end %#ok<AGROW>
            lines = [lines; ""]; %#ok<AGROW>
        end
        for k = 1:size(L.outs, 1)
            if startsWith(L.outs{k,2}, "Bus:") || ~contains(L.outs{k,2}, " ")
                lines = [lines; busLines(sec, "OUT", L.outs{k,1}, L.outs{k,2}, "all"); ""]; %#ok<AGROW>
            end
        end
        if ~isempty(L.outSignals), lines = [lines; L.outSignals; ""]; end %#ok<AGROW>
        lines = [lines; "WHAT IT DOES"; bullets(L.does); ""; "LIMITATIONS / LATER"; bullets(L.limits)]; %#ok<AGROW>
        placeNote(sys, lines);
    end
end

%% Layer definitions
function L = layers()
    L = struct("name", {}, "title", {}, "acr", {}, "ins", {}, "params", {}, "outs", {}, ...
               "outSignals", {}, "does", {}, "limits", {});
    L(end+1) = struct("name", "MEAS", ...
        "title", "MEAS - measurement layer: calibrate raw sensor values   (C: MEAS_Step, every BMS_Ts)", ...
        "acr", ["MEAS" "BMS" "g" "ts"], ...
        "ins", {{"meas", "SENS_measBus", "all"}}, "params", strings(1,0), ...
        "outs", {{"measData", "BMS_measData"}}, "outSignals", strings(0,1), ...
        "does", ["Copies every measurement and its timestamp into the BMS's own bus"], ...
        "limits", ["No calibration yet: later stored gain/offset per channel and current re-zero while the switch is open"]);
    L(end+1) = struct("name", "PLAUS", ...
        "title", "PLAUS - plausibility layer: is each sensor channel believable?   (C: PLAUS_Step; logic plausCheck.m)", ...
        "acr", ["PLAUS" "SOA" "DIAG" "ts" "V/I/T/C"], ...
        "ins", {{"measData", "BMS_measData", "all"; "pwr", "BMS_pwrData", "boot"}}, ...
        "params", ["BMS_vPlausRange" "BMS_iPlausMax" "BMS_tPlausRange" "BMS_tStale" "BMS_Ts"], ...
        "outs", {{"plausData", "BMS_plausData"}}, "outSignals", strings(0,1), ...
        "does", ["Channel valid = first sample received AND value inside its plausible SENSOR range"
                 "  AND timestamp advanced within BMS_tStale"
                 "Start-up: a sensor type is invalid until its FIRST new sample (timestamp change); values before"
                 "  that are power-up contents. measReady latches true once all four types (V/I/T/C) have delivered"
                 "Detects sensor and wiring faults only; cell limits are checked in SOA"
                 "Reports each step as seen, no time filter (DIAG debounces)"], ...
        "limits", ["One timestamp per sensor type: staleness applies to all 13 voltages (or all 26 temperatures) together"
                   "No rate-of-change check"]);
    L(end+1) = struct("name", "BMSVL", ...
        "title", "BMSVL - validated-values layer: pack extremes and overall validity   (C: BMSVL_Step; logic validExtremes.m)", ...
        "acr", ["BMSVL" "PLAUS" "SOA" "SE" "g"], ...
        "ins", {{"plausData", "BMS_plausData", "all"; "pwr", "BMS_pwrData", "boot"}}, "params", "BMS_soaLim", ...
        "outs", {{"validData", "BMS_validData"}}, "outSignals", strings(0,1), ...
        "does", ["vMin/vMax and tMin/tMax over VALID channels only: an implausible channel is reported once,"
                 "  as invalid, never also as an SOA limit violation"
                 "No valid channel of a type: the last valid extreme is held; before the first valid sample"
                 "  the extremes sit mid-way in the MOL window of BMS_soaLim (no fault: DIAG waits for measReady)"
                 "allValid = AND of every vValid, iValid, tValid and cValid; measReady passed through"], ...
        "limits", ["Extremes give the worst value, not yet WHICH group or sensor (needed for fault codes)"]);
    L(end+1) = struct("name", "SOA", ...
        "title", "SOA - safe-operating-area layer: is any quantity beyond a limit RIGHT NOW?   (C: SOA_Step; logic soaCheck.m)", ...
        "acr", ["SOA" "MOL" "RSL" "MSL" "DIAG" "dchg/chg"], ...
        "ins", {{"validData", "BMS_validData", ["iPack" "vMin" "vMax" "tMin" "tMax"]}}, ...
        "params", ["BMS_soaLim" "BMS_iRest"], ...
        "outs", {{"soaData", "BMS_soaData"}}, "outSignals", strings(0,1), ...
        "does", ["Compares the extremes and the current with three limits per quantity: [MOL RSL MSL]; true = exceeded"
                 "Charging (iPack < -BMS_iRest) selects the tighter charge temperature window"
                 "Instantaneous: one comparison per step, no time filter, no fault decision (that is DIAG's job)"], ...
        "limits", ["MSLs from the Samsung INR18650-35E specification Ver. 1.1 x 7 cells, except the vMax MSL (4.25 V,"
                   "  engineering judgement: 4.20 V is the normal charge voltage); MOL and RSL margins are placeholders"]);
    L(end+1) = struct("name", "DIAG", ...
        "title", "DIAG - diagnostics layer: has a problem lasted long enough to be a FAULT?   (C: DIAG_Step; logic diagDebounce.m)", ...
        "acr", ["DIAG" "SOA" "MSL" "MOL" "RSL" "PLAUS"], ...
        "ins", {{"soaData", "BMS_soaData", "all"; "validData", "BMS_validData", ["allValid" "measReady"]; "pwr", "BMS_pwrData", ["awake" "boot"]}}, ...
        "params", ["BMS_tDiagSet" "BMS_tDiagClear" "BMS_Ts"], ...
        "outs", {{"diag", "DIAG_bus"}}, "outSignals", strings(0,1), ...
        "does", ["Nothing is evaluated until measReady (every sensor type has delivered its first sample)"
                 "Fatal conditions: any MSL exceeded (from SOA) or any measurement implausible (allValid false)"
                 "A fault SETS once its condition has persisted BMS_tDiagSet; CLEARS once absent for BMS_tDiagClear"
                 "Debounced, not latched: remembering faults, retries and latching are in the BMS state machine"], ...
        "limits", ["MOL and RSL are not used yet (future warnings and current derating)"
                   "Switch faults (stuck open, welded) are found by the state machine and are not reported here"]);
    L(end+1) = struct("name", "SE", ...
        "title", "SE - state-estimation layer: SOC per group, coulomb-counting variant (Simulink blocks; SOH not yet estimated)   (C: SE_Step)", ...
        "acr", ["SE" "SOC" "SOH" "OCV" "RTC" "NVM" "g"], ...
        "ins", {{"validData", "BMS_validData", ["vGroup" "iPack" "allValid" "measReady"]; "hw", "BMS_hwIn", ["rtcNow" "nvm"]; "pwr", "BMS_pwrData", ["awake" "boot" "reset"]}}, ...
        "params", ["BMS_ocvSoc" "BMS_ocvV" "BMS_Qnom" "BMS_tRelax" "BMS_socMismatchTol" "BMS_iRest" "BMS_tRestRecal" "BMS_Ts"], ...
        "outs", {{"seData", "BMS_seData"}}, "outSignals", strings(0,1), ...
        "does", ["Blocks: ocvToSoc -> startupSoc (decision) | initControl (when) | restRecal (rest timer) | coulombCounter | captureInit (holds result)"
                 "Start-up, after every power-on or reset, on the first step with every measurement valid (switch open):"
                 "  socOcv = OCV-table inverse of each group voltage; rest = rtcNow - nvm.tSave"
                 "  record invalid or rest < 0 -> OCV | |stored - OCV| > BMS_socMismatchTol on any group"
                 "  (recharged or swapped while off) -> OCV, flagged | reset or rest >= BMS_tRelax -> OCV | else stored SOC"
                 "Then coulomb counting: SOC -= iPack * Ts / (3600 * BMS_Qnom * sohQ), limited to 0..1"
                 "At rest (as foxBMS): |iPack| < BMS_iRest for BMS_tRestRecal -> SOC = OCV while the rest lasts (socRecal)"
                 "socPack = lowest group SOC; nvm = record to save (valid once SOC is initialised)"], ...
        "limits", ["sohR and sohQ are constant 1: NO state-of-health estimation yet (placeholders); OCV table and BMS_tRelax are placeholders"
                   "A stored-SOC error smaller than BMS_socMismatchTol is kept after a short rest; EKF / RLS variants later"
                   "At-rest OCV is the terminal voltage under the hotel load (< BMS_iRest): small IR error, as foxBMS"]);
    L(end+1) = struct("name", "BMS", ...
        "title", "BMS - system state machine: when the main switch may be closed   (C: BMS_Step; chart stateMachine)", ...
        "acr", ["BMS" "DIAG" "g"], ...
        "ins", {{"diag", "DIAG_bus", "anyFatal"; "validData", "BMS_validData", ["allValid" "contactorFb"]; "pwr", "BMS_pwrData", ["awake" "boot"]}}, ...
        "params", ["BMS_tInitSettle" "BMS_tInitMax" "BMS_tCloseMax" "BMS_tRecover" "BMS_nRetryMax" "BMS_tRetryReset"], ...
        "outs", {cell(0,2)}, ...
        "outSignals", ["OUT  state        (Enum: BMS_state)  OFF | INITIALIZATION = switch open, checking | NORMAL = switch closed | ERROR = fault, switch open"
                       "OUT  contactorCmd (boolean)          main switch command: true = close"], ...
        "does", ["OFF (at power-up, and after a power long press): switch open, nothing else runs; ON when awake"
                 "ON: entered on wake, re-entered on reset (boot): retries and latch cleared, starts in INITIALIZATION"
                 "INITIALIZATION: switch open; when allValid, no fatal fault and feedback reads open (not welded) hold for"
                 "  BMS_tInitSettle, command close; NORMAL once feedback confirms within BMS_tCloseMax, else ERROR"
                 "NORMAL: a fatal fault, or the feedback opening unexpectedly -> ERROR"
                 "ERROR: switch open; retry (back to INITIALIZATION) after faults clear for BMS_tRecover;"
                 "  stays in ERROR after BMS_nRetryMax consecutive errors (count reset after BMS_tRetryReset in NORMAL;"
                 "  latch cleared by power off/on or reset)"], ...
        "limits", ["ERROR reason for switch faults is not reported in diag; no precharge step"]);
end

function L = addPwr(L)
    L(end+1) = struct("name", "PWR", ...
        "title", "PWR - power and reset buttons (long presses)   (C: PWR_Step; logic pwrManager.m)", ...
        "acr", ["BMS" "RTC" "NVM"], ...
        "ins", {{"hw", "BMS_hwIn", ["powerBtn" "resetBtn"]}}, ...
        "params", ["BMS_tPowerPress" "BMS_tResetPress" "BMS_Ts"], ...
        "outs", {{"pwrData", "BMS_pwrData"}}, "outSignals", strings(0,1), ...
        "does", ["Starts OFF (awake = false): the switch stays open until someone switches the battery on"
                 "Power held BMS_tPowerPress: OFF -> on (awake, boot) or on -> OFF; acts once per press"
                 "Reset held BMS_tResetPress: restart (boot + reset; wakes the BMS if off): every layer restarts,"
                 "  SOC from OCV, ERROR latch cleared, start-up checks run again"], ...
        "limits", ["Hardware: the power button drives a power latch; the BMS holds its own supply while on and"
                   "  releases it at switch-off (after the record is saved). Here OFF is modelled as an inactive state"]);
end

function L = addLog(L)
    L(end+1) = struct("name", "LOG", ...
        "title", "LOG - event log: time-stamped INFO / MINOR / MAJOR / FAULT records   (C: LOG_Step; logic logEvents.m)", ...
        "acr", ["BMS" "DIAG" "SOA" "MOL" "RSL" "MSL" "g"], ...
        "ins", {{"validData", "BMS_validData", ["iPack" "vMin" "vMax" "tMin" "tMax" "measReady" "vMinIdx" "vMaxIdx" "tMinIdx" "tMaxIdx"]
                 "diag", "DIAG_bus", ["sensorInvalid" "level" "excursion"]
                 "plausData", "BMS_plausData", ["vValid" "iValid" "tValid" "cValid"]
                 "seData", "BMS_seData", ["socPack" "socInitMethod" "socInitMismatch" "socInitDiff" "socInitDiffIdx" "socInitRest" "socRecal"]
                 "pwr", "BMS_pwrData", "all"}}, ...
        "params", ["BMS_soaLim" "BMS_iRest" "BMS_socMismatchTol" "BMS_Ts"], ...
        "outs", {{"events", "BMS_event"}}, ...
        "outSignals", ["IN   state (BMS_state), contactorCmd (bool), errorCause (BMS_eventCode), latched (bool)  from the state machine"
                       "OUT  events = 6 slots of BMS_event per step, most severe first (severity NONE = empty slot)"
                       "OUT  eventCount (uint32) records since start-up | eventDropped (uint32) records lost: >6 in one step"], ...
        "does", ["INFO: every state change, start-up check begun (attempt n) / passed, switch closed, first full sample set,"
                 "  SOC initialised (method, rest time); MINOR: stored SOC disagreed with OCV (recharged / swapped while off)"
                 "MINOR / MAJOR / FAULT: a quantity's debounced level rose past MOL / RSL / MSL; record again when it falls"
                 "  location = worst group (voltage) or sensor (temperature), value = that reading, limit = the limit crossed"
                 "MAJOR: MSL excursion (exceeded, but shorter than BMS_tDiagSet)"
                 "FAULT: sensor type invalid (location = channel, 0 = several); ERROR cause; RETRY_LIMIT when latched"
                 "A 'cleared' record keeps the severity of what cleared, with active = false"], ...
        "limits", ["Records leave the BMS on BMS_outBus only (Pi bring-up: printed to the console)"
                   "Time is BMS run time (task count x BMS_Ts), not wall-clock time"]);
end

function G = glossary()
    G = dictionary( ...
        ["BMS" "MEAS" "PLAUS" "BMSVL" "SOA" "MOL" "RSL" "MSL" "DIAG" "SE" "SOC" "SOH" "OCV" "g" "ts" "dchg/chg" "V/I/T/C" "RTC" "NVM"], ...
        ["BMS = battery management system" "MEAS = measurement layer" "PLAUS = plausibility layer" ...
         "BMSVL = validated-values layer" "SOA = safe operating area" "MOL = maximum operating limit (lowest level)" ...
         "RSL = recommended safety limit (middle)" "MSL = maximum safety limit (cell specification, highest)" ...
         "DIAG = diagnostics layer" "SE = state estimation" "SOC = state of charge (0..1)" ...
         "SOH = state of health (1 = new)" "OCV = open-circuit voltage" ...
         "group = 7 cells in parallel = one of the 13 series elements" "ts = timestamp of a sample" ...
         "dchg/chg = discharge/charge (current discharge-positive)" "V/I/T/C = voltage/current/temperature/contactor (main switch)" ...
         "RTC = real-time clock (battery-backed)" "NVM = non-volatile memory (kept over a power cycle)"]);
end

%% Text builders
function out = bullets(items)
    % "- " before each item; items starting with two spaces continue the previous one
    items = items(:);
    cont = startsWith(items, "  ");
    out = items;
    out(~cont) = "  - " + items(~cont);
    out(cont)  = "    " + strip(items(cont), "left");
end

function lines = busLines(sec, dir, port, busName, used)
    busName = erase(string(busName), "Bus: ");
    e = find(sec, "Name", busName); b = getValue(e(1));
    lines = sprintf("%s  %s : %s", dir, port, busName);
    for x = b.Elements'
        mark = " ";
        if dir == "IN " && (any(used == "all") || any(used == x.Name)), mark = "*"; end
        if prod(x.Dimensions) > 1, dims = sprintf("%dx1", prod(x.Dimensions)); else, dims = "1"; end
        unit = string(x.Unit); if unit == "", unit = "-"; end
        if startsWith(x.DataType, "boolean"), unit = "bool"; end
        lines(end+1, 1) = sprintf("  %s %-14s %-5s %-5s %s", mark, x.Name, dims, unit, x.Description); %#ok<AGROW>
    end
    if dir == "IN " && ~any(used == "all"), lines(1) = lines(1) + "   (* = used here)"; end
end

function lines = paramLines(sec, name)
    e = find(sec, "Name", name); p = getValue(e(1)); v = p.Value;
    if isstruct(v)
        lines = sprintf("  %-16s %s", name, p.Description);
        for f = string(fieldnames(v))'
            x = v.(f);
            if startsWith(f, "t"), s = sprintf("%s K  (%s degC)", mat2str(x, 5), mat2str(x - 273.15, 4));
            else, s = mat2str(x, 4) + " " + unitOf(f); end
            lines(end+1, 1) = sprintf("      %-9s %s", f, s); %#ok<AGROW>
        end
    else
        lines = sprintf("  %-16s = %s %s   %s", name, mat2str(v, 5), p.Unit, p.Description);
    end
end

function u = unitOf(f)
    if startsWith(f, "v"), u = "V"; elseif startsWith(f, "i"), u = "A"; else, u = ""; end
end

function placeNote(sys, lines)
    % Replace the layer's previous note (any note whose first line starts with the layer name)
    layer = extractAfter(sys, "/");
    a = find_system(sys, "FindAll", "on", "SearchDepth", 1, "Type", "annotation");
    for k = 1:numel(a)
        t = string(get_param(a(k), "PlainText"));
        if startsWith(t, layer + " - ") || startsWith(t, layer + "  - "), delete(get_param(a(k), "Object")); end
    end
    b = find_system(sys, "SearchDepth", 1, "Type", "block"); b = b(2:end);
    p = cell2mat(get_param(b, "Position")); x0 = min(p(:,1)); y0 = min(p(:,2));
    an = Simulink.Annotation(char(sys), char(strjoin(lines, newline)));
    an.FontName = "Consolas"; an.FontSize = 10; an.HorizontalAlignment = "left";
    h = 13.5 * numel(lines) + 10; w = 7 * max(strlength(lines)) + 20;
    an.Position = [x0, y0 - 40 - h, x0 + w, y0 - 40];
end
