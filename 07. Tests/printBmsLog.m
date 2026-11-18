function T = printBmsLog(out, quiet)
%PRINTBMSLOG Readable BMS event log from a platform simulation.
%   T = printBmsLog(out) prints every log record the BMS produced in the run (logged
%   BMS output, bmsOutLog) and returns them as a table. printBmsLog(out, true) only
%   returns the table.
%
%   Each line:  time  severity  fault code  description
%   Fault codes give the highest location the hardware can resolve:
%     voltages per group:      OV-M3-G05      (module 3, group 5)
%     temperatures per sensor: OT-M3-G05-T09  (sensor 9 = group 5, buried cell)
%     current, pack level:     OCD / OCC      (discharge / charge)
%     sensors:                 SV-M4-G07, ST-ALL (several channels), SI, SC
%   Module of each group (13S7P tube): groups 1-2 M1 (2S7P, slice 1), 3-4 M2, 5-6 M3,
%   7-8 M4, 9-10 M5, 11-12 M6, 13 M7 (1S7P half slice). Temperature sensors: 2 per group,
%   odd = buried cell, even = outer cell.
%   Limit levels: MOL (lowest), RSL, MSL (cell specification, opens the switch).

    arguments
        out
        quiet (1,1) logical = false
    end
    b = out.logsout.get("bmsOutLog").Values;  E = b.events;
    rows = {};
    for i = 1:numel(E(1).severity.Time)
        for s = 1:numel(E)
            sev = E(s).severity.Data(i);
            if sev == BMS_severity.NONE, continue, end
            r.t = E(s).t.Data(i);  r.severity = string(sev);  r.code = E(s).code.Data(i);
            r.active = E(s).active.Data(i);  r.location = double(E(s).location.Data(i));
            r.level = double(E(s).level.Data(i));  r.value = E(s).value.Data(i);
            r.limit = E(s).limit.Data(i);  r.state = string(E(s).state.Data(i));
            [r.faultCode, r.text] = describe(r);
            rows{end+1, 1} = r; %#ok<AGROW>
        end
    end
    if isempty(rows)
        T = table();  if ~quiet, disp("(no log records)"); end
        return
    end
    T = struct2table([rows{:}]');
    if ~quiet
        for k = 1:height(T)
            fprintf("%8.2f s  %-5s  %-15s  %s\n", T.t(k), T.severity(k), T.faultCode(k), T.text(k));
        end
        fprintf("%d records, %d dropped\n", b.eventCount.Data(end), b.eventDropped.Data(end));
    end
end

function [fc, txt] = describe(r)
    moduleOf = [1 1 2 2 3 3 4 4 5 5 6 6 7];
    lvlName = ["MOL" "RSL" "MSL"];
    c = r.code;  g = r.location;
    suffix = "";  if ~r.active, suffix = " - cleared"; end
    switch c
        case {BMS_eventCode.OVER_VOLTAGE, BMS_eventCode.UNDER_VOLTAGE}
            pre = "OV"; word = "over-voltage"; cmp = ">";
            if c == BMS_eventCode.UNDER_VOLTAGE, pre = "UV"; word = "under-voltage"; cmp = "<"; end
            fc = sprintf("%s-M%d-G%02d", pre, moduleOf(max(g,1)), g);
            txt = sprintf("%s, module %d, group %d: %.3f V %s %.3f V (%s)", word, moduleOf(max(g,1)), g, r.value, cmp, r.limit, lvlName(max(r.level,1)));
        case {BMS_eventCode.OVER_TEMP, BMS_eventCode.UNDER_TEMP}
            pre = "OT"; word = "over-temperature"; cmp = ">";
            if c == BMS_eventCode.UNDER_TEMP, pre = "UT"; word = "under-temperature"; cmp = "<"; end
            grp = ceil(max(g,1)/2);  cell = "outer";  if mod(g, 2) == 1, cell = "buried"; end
            fc = sprintf("%s-M%d-G%02d-T%02d", pre, moduleOf(grp), grp, g);
            txt = sprintf("%s, module %d, group %d, %s cell: %.1f degC %s %.1f degC (%s)", word, moduleOf(grp), grp, cell, r.value - 273.15, cmp, r.limit - 273.15, lvlName(max(r.level,1)));
        case {BMS_eventCode.OVER_CURRENT_DCHG, BMS_eventCode.OVER_CURRENT_CHG}
            fc = "OCD"; word = "discharge";
            if c == BMS_eventCode.OVER_CURRENT_CHG, fc = "OCC"; word = "charge"; end
            txt = sprintf("%s over-current: %.1f A > %.1f A (%s)", word, r.value, r.limit, lvlName(max(r.level,1)));
        case {BMS_eventCode.SENSOR_V_INVALID, BMS_eventCode.SENSOR_T_INVALID}
            isV = c == BMS_eventCode.SENSOR_V_INVALID;
            pre = "SV"; what = "voltage";  if ~isV, pre = "ST"; what = "temperature"; end
            if g == 0
                fc = pre + "-ALL";  txt = sprintf("%s measurement invalid on %d channels", what, round(r.value));
            elseif isV
                fc = sprintf("SV-M%d-G%02d", moduleOf(g), g);  txt = sprintf("voltage measurement invalid, module %d, group %d", moduleOf(g), g);
            else
                grp = ceil(g/2);  fc = sprintf("ST-M%d-G%02d-T%02d", moduleOf(grp), grp, g);
                txt = sprintf("temperature measurement invalid, sensor %d (module %d, group %d)", g, moduleOf(grp), grp);
            end
            if ~r.active, txt = replace(txt, " invalid", " valid again"); end
        case BMS_eventCode.SENSOR_I_INVALID
            fc = "SI";  txt = "current measurement invalid";
        case BMS_eventCode.SENSOR_C_INVALID
            fc = "SC";  txt = "main switch feedback stale";
        case BMS_eventCode.STATE_CHANGE
            fc = "STATE";  txt = "state -> " + string(BMS_state(r.location));
        case BMS_eventCode.START_CHECK_BEGIN
            fc = "START";  txt = sprintf("start-up check begun (attempt %d)", g);
        case BMS_eventCode.START_CHECK_PASSED
            fc = "START";  txt = sprintf("start-up check passed (attempt %d): closing main switch", g);
        case BMS_eventCode.RETRY_LIMIT
            fc = "ERR-LATCHED";  txt = sprintf("retry limit reached after %d attempts: ERROR latched until power off/on or reset", g);
        case BMS_eventCode.SOC_INIT
            how = ["from the stored SOC", "blending stored SOC and OCV", "from OCV"];
            fc = "SOC";
            if r.value < 0, txt = sprintf("SOC initialised %s (no stored record used: none valid, or reset)", how(max(min(g,3),1)));
            else, txt = sprintf("SOC initialised %s (rest %.1f min)", how(max(min(g,3),1)), r.value/60); end
        case BMS_eventCode.POWER_ON
            fc = "PWR";  txt = "power button: BMS switched on";
        case BMS_eventCode.POWER_OFF
            fc = "PWR";  txt = "power button: main switch opened, record saved, BMS off";
        case BMS_eventCode.RESET
            fc = "RESET";  txt = "reset button: restart with SOC from OCV, ERROR latch cleared";
        case BMS_eventCode.SOC_MISMATCH
            fc = sprintf("SOC-MIS-M%d-G%02d", moduleOf(max(g,1)), g);
            txt = sprintf("stored SOC differs from OCV by %.1f %% (group %d) > %.1f %%: recharged or swapped while off, OCV used", 100*r.value, g, 100*r.limit);
        case BMS_eventCode.MEAS_READY
            fc = "MEAS";  txt = "first full measurement set received (voltage, current, temperature, switch feedback)";
        case BMS_eventCode.SWITCH_CLOSED
            fc = "SWITCH";  txt = "main switch closed and confirmed by feedback";
        case BMS_eventCode.DIAG_FAULT
            fc = "ERR-DIAG";  txt = "ERROR: debounced DIAG fault (see the fault records at the same time)";
        case BMS_eventCode.SWITCH_STUCK_OPEN
            fc = "ERR-SW-OPEN";  txt = "ERROR: main switch commanded closed, feedback did not confirm";
        case BMS_eventCode.SWITCH_WELDED
            fc = "ERR-SW-WELD";  txt = "ERROR: main switch feedback reads closed while commanded open (welded)";
        case BMS_eventCode.SWITCH_OPENED_UNEXPECTEDLY
            fc = "ERR-SW-LOST";  txt = "ERROR: main switch opened in NORMAL without a DIAG fault";
        case BMS_eventCode.INIT_TIMEOUT
            fc = "ERR-INIT";  txt = "ERROR: start-up check not passed in time";
        otherwise
            fc = string(c);  txt = lower(replace(string(c), "_", " "));
    end
    if r.active && r.severity == "MAJOR" && r.level == 3, txt = txt + " - brief excursion, not a fault"; end
    txt = txt + suffix;
end
