function hw = hwEmulator(t, bmsState, nvmSaved, rtcStart, nvm0, powerPress, resetPress)
%HWEMULATOR Platform stand-in for the BMS board peripherals (BMS_HW block).
%   hw = hwEmulator(t, bmsState, nvmSaved, rtcStart, nvm0, powerPress, resetPress)
%   t           run time, s
%   bmsState    BMS state (from the BMS output, delayed one BMS step)
%   nvmSaved    record the BMS asks to save (BMS_outBus.nvm, same delay)
%   rtcStart    real-time clock at the start of the run, s
%   nvm0        record in non-volatile memory at the start of the run
%   powerPress, resetPress   button presses, rows [start duration] s (negative start = unused)
%   hw          BMS_hwIn
%
%   Non-volatile memory: holds nvm0 until the BMS switches off; the record the BMS
%   outputs at that moment is stored and read back at the next power-up (as the Pi's
%   wrapper does: write at shutdown, read at boot). Platform only: never part of the BMS.
%   Called from one MATLAB Function block only (memory kept in persistent variables).

    persistent mem prevOff
    if isempty(mem)
        mem = nvm0;  prevOff = true;
    end
    isOff = bmsState == BMS_state.OFF;
    if isOff && ~prevOff && nvmSaved.valid
        mem = nvmSaved;
    end
    prevOff = isOff;

    hw.rtcNow   = rtcStart + t;
    hw.nvm      = mem;
    hw.powerBtn = any(powerPress(:,1) >= 0 & t >= powerPress(:,1) & t < powerPress(:,1) + powerPress(:,2));
    hw.resetBtn = any(resetPress(:,1) >= 0 & t >= resetPress(:,1) & t < resetPress(:,1) + resetPress(:,2));
end
