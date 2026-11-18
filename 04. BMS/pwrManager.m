function pw = pwrManager(hw, tPower, tReset, Ts)
%PWRMANAGER BMS PWR layer: power and reset buttons (long presses).
%   pw = pwrManager(hw, tPower, tReset, Ts)
%   hw      BMS_hwIn (powerBtn, resetBtn)
%   tPower  power long-press time, s: switches on (from off) or off
%   tReset  reset long-press time, s: restart with SOC from OCV, ERROR latch cleared
%   Ts      BMS task period, s (called once per task)
%   pw      BMS_pwrData: awake, and one-step pulses boot, reset, powerOn, powerOff
%
%   The BMS starts off (awake = false). Each long press acts once; the button must be
%   released before it can act again, so holding it does not toggle repeatedly.
%   A reset also wakes the BMS if it was off. boot tells every layer to restart as after
%   a real power-up (in hardware the power latch removes and restores the supply; here
%   the layers clear their own history).
%   Called from one MATLAB Function block only (state kept in persistent variables).

    persistent awake nP nR armedP armedR
    if isempty(awake)
        awake = false;  nP = 0;  nR = 0;  armedP = true;  armedR = true;
    end
    nPow = max(1, round(tPower / Ts));
    nRes = max(1, round(tReset / Ts));
    if hw.powerBtn, nP = nP + 1; else, nP = 0; armedP = true; end
    if hw.resetBtn, nR = nR + 1; else, nR = 0; armedR = true; end

    boot = false;  reset = false;  on = false;  off = false;
    if armedR && nR >= nRes
        armedR = false;  reset = true;  boot = true;
        if ~awake, awake = true; on = true; end
    elseif armedP && nP >= nPow
        armedP = false;
        if awake
            awake = false;  off = true;
        else
            awake = true;  on = true;  boot = true;
        end
    end

    % Fields in the order of BMS_pwrData
    pw.awake    = awake;
    pw.boot     = boot;
    pw.reset    = reset;
    pw.powerOn  = on;
    pw.powerOff = off;
end
