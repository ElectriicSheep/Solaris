function se = socEstimate(v, hw, pw, ocvSoc, ocvV, Qnom, tRelax, tol, Ts)
%SOCESTIMATE BMS SE layer (coulomb-counting variant): start-up SOC, then charge counting.
%   se = socEstimate(v, hw, pw, ocvSoc, ocvV, Qnom, tRelax, tol, Ts)
%   v       BMS_validData (vGroup, iPack, allValid, measReady)
%   hw      BMS_hwIn (rtcNow, nvm = record read from non-volatile memory at power-up)
%   pw      BMS_pwrData (awake; boot = restart as after power-up; reset = force SOC from OCV)
%   ocvSoc, ocvV   OCV table (SOC breakpoints, group OCV in V, strictly increasing)
%   Qnom    nominal group capacity, Ah;  tRelax  rest time for full OCV trust, s
%   tol     largest stored-vs-OCV SOC difference explained by OCV error
%   Ts      BMS task period, s (called once per task)
%   se      BMS_seData
%
%   Start-up (after every power-up or reset, on the first awake step with every
%   measurement valid; the main switch is open, so the voltages are unloaded):
%     - reset long press                                   -> SOC = socOcv       (method 3)
%     socOcv = OCV table inverse of each group voltage; rest = rtcNow - nvm.tSave
%     - record invalid, or rest < 0 (clock error)          -> SOC = socOcv       (method 3)
%     - max |nvm.socGroup - socOcv| > tol: recharged or swapped while off
%                                                          -> SOC = socOcv       (method 3, mismatch)
%     - otherwise blend by rest: w = min(1, rest/tRelax),
%       SOC = w*socOcv + (1-w)*stored                       (method 1 if w = 0, 2 if 0<w<1, 3 if w = 1)
%   Then: SOC(k) = SOC(k-1) - iPack*Ts / (3600 * Qnom * sohQ), limited to 0..1, while awake
%   (off: no counting; the switch is open).
%   Before initialisation the output SOC is the stored value (0 if no valid record).
%   The record to save (se.nvm) is valid only once SOC has been initialised.
%   Called from one MATLAB Function block only (state kept in persistent variables).

    nG = numel(v.vGroup);
    persistent soc done method mism dMax dIdx rest forceOcv
    if isempty(done) || pw.boot
        if isempty(done), soc = zeros(nG, 1); end
        if hw.nvm.valid && ~pw.reset, soc = hw.nvm.socGroup; end
        done = false;  method = uint8(0);  mism = false;  dMax = 0;  dIdx = uint8(0);  rest = 0;
        forceOcv = pw.reset;
    end
    sohQ = ones(nG, 1);
    sohR = ones(nG, 1);

    if ~done
        if pw.awake && v.measReady && v.allValid
            vc = min(max(v.vGroup, ocvV(1)), ocvV(end));
            socOcv = interp1(ocvV(:), ocvSoc(:), vc, "linear");
            rest = hw.rtcNow - hw.nvm.tSave;
            if forceOcv || ~hw.nvm.valid || rest < 0
                soc = socOcv;  method = uint8(3);
                if forceOcv || ~hw.nvm.valid, rest = -1; end      % -1 = no stored record used
            else
                d = abs(hw.nvm.socGroup - socOcv);
                [dMax, k] = max(d);  dIdx = uint8(k);
                if dMax > tol
                    soc = socOcv;  method = uint8(3);  mism = true;
                else
                    w = min(1, rest / tRelax);
                    soc = w * socOcv + (1 - w) * hw.nvm.socGroup;
                    if w <= 0, method = uint8(1); elseif w < 1, method = uint8(2); else, method = uint8(3); end
                end
            end
            done = true;
        end
    elseif pw.awake
        soc = soc - v.iPack * Ts ./ (3600 * Qnom * sohQ);
        soc = min(max(soc, 0), 1);
    end

    % Fields in the order of BMS_seData
    se.socGroup        = soc;
    se.sohR            = sohR;
    se.sohQ            = sohQ;
    se.socPack         = min(soc);
    se.sohPack         = min(sohQ);
    se.socInitMethod   = method;
    se.socInitMismatch = mism;
    se.socInitDiff     = dMax;
    se.socInitDiffIdx  = dIdx;
    se.socInitRest     = rest;
    se.nvm.socGroup    = soc;
    se.nvm.tSave       = hw.rtcNow;
    se.nvm.valid       = done;
end
