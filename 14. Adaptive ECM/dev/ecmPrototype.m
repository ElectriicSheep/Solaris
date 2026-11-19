function R = ecmPrototype(P, hours)
%ECMPROTOTYPE Reference MATLAB implementation of the plant, sensors and adaptive
% estimator, for design and for checking the Simulink blocks. Not the deliverable.
Ts = P.Ts; nG = P.nG; N = round(hours*3600/Ts); dec = round(P.TsRc/Ts);
pl = P.plant; es = P.est; se = P.sens;
rs = RandStream("mt19937ar","Seed",se.noiseSeed);
% plant state
z = pl.soc0*ones(1,nG); v1 = zeros(1,nG); T = pl.T0C*ones(1,nG);
% schedule
mode = 0; tMode = 0; kDis = 0; iCmd = 0;
% estimator state
tab.r0 = es.init.r0; tab.r1 = es.init.r1; tab.tau = es.init.tau; cnt = es.init.count; Qh = es.init.Q;
zh = []; v1h = zeros(1,nG); p11 = es.ekfP0(1,1)*ones(1,nG); p12 = zeros(1,nG); p22 = es.ekfP0(2,2)*ones(1,nG);
th0 = mean(reshape(tab.r0,[],nG)); p0 = es.p0Rc(1)*0 + es.p0R0*ones(1,nG);
thRc = [zeros(1,nG); zeros(1,nG); zeros(1,nG)]; Prc = repmat(es.p0Rc,1,1,nG);
% initial guess of a, c from the tables
for g=1:nG, tau0=tab.tau(6,2,g); a0=exp(-P.TsRc/tau0); thRc(:,g)=[a0; tab.r1(6,2,g)*(1-a0); 0]; end
vPrev = []; iPrev = 0; yBuf = zeros(dec,nG); iBuf = zeros(dec,1); ipBuf = zeros(dec,1); yPP = []; rcMode = 'point'; if isfield(P,'dbg') && isfield(P.dbg,'rcMode'), rcMode = P.dbg.rcMode; end
yAvgPrev = []; iAvgPrev = []; iAvgFull = 0; xAuxPrev = zeros(1,nG); exc = 0; iAprevExc = 0;
S1 = es.capW0*Qh; S2 = es.capW0*ones(1,nG); Ah = zeros(1,nG); tRest = 0; zRestPrev = nan(1,nG); restDone = false;
segSlope = diff(es.ocv)./diff(es.socBp);
nLog = floor(N/dec); L.t = zeros(nLog,1); L.z = zeros(nLog,nG); L.zh = L.z; L.r0 = L.z; L.r1=L.z; L.tau=L.z; L.Qh=L.z;
L.r0t = L.z; L.r1t=L.z; L.taut=L.z; L.th0=L.z; L.r1rls=L.z; L.taurls=L.z; L.i=zeros(nLog,1); L.v=L.z; L.T=L.z; L.Wh=L.z; L.mode=zeros(nLog,1);
Wh = zeros(1,nG); li = 0;
for k = 1:N
    t = (k-1)*Ts;
    % ---- schedule (uses truth) ----
    vTrue = interpG(pl.ocv,pl,z,T) - v1 - interpG(pl.r0,pl,z,T)*iCmd; %#ok<NASGU>
    switch mode
        case 0, iCmd = 0; if tMode >= P.load.tRest0, mode = 1; tMode = 0; end
        case 1, kDis = kDis + 1; iCmd = P.load.profile(mod(kDis-1,P.load.N)+1);
                if min(z) <= P.load.socLow, mode = 2; tMode = 0; iCmd = 0; end
        case 2, iCmd = 0; if tMode >= P.load.tRest, mode = 3; tMode = 0; end
        case 3, iCmd = -P.load.iChg; vNow = interpG(pl.ocv,pl,z,T) - v1 - interpG(pl.r0,pl,z,T)*iCmd;
                if max(z) >= P.load.socHigh || max(vNow) >= P.load.vMax, mode = 4; tMode = 0; iCmd = 0; end
        case 4, iCmd = 0; if tMode >= P.load.tRest, mode = 1; tMode = 0; end
    end
    tMode = tMode + Ts; i = iCmd;
    % ---- plant output at t (current i applied from t) ----
    R0 = interpG(pl.r0,pl,z,T); R1 = interpG(pl.r1,pl,z,T); tau = interpG(pl.tau,pl,z,T);
    v = interpG(pl.ocv,pl,z,T) - v1 - R0*i;
    % ---- sensors ----
    vm = round((v + se.vNoise*randn(rs,1,nG))/se.vLsb)*se.vLsb;
    im = round((i + se.iOffset + se.iNoise*randn(rs))/se.iLsb)*se.iLsb;
    Tm = round((se.thermMap*T' + se.tNoise*randn(rs,7,1))/se.tLsb)*se.tLsb; Tg = Tm(se.groupTherm)';
    % ---- estimator ----
    if isempty(zh), zh = interp1(es.ocv, es.socBp, vm, "linear", "extrap"); zh = min(max(zh,0),1); vPrev = vm; iPrev = im; zL0 = zh; TL0 = Tg; zLrc = zh; TLrc = Tg; end
    [R0t,R1t,taut,w,idx] = tabInterp(tab, es, zh, Tg);
    % EKF predict (with previous current)
    a = exp(-Ts./taut);
    Quse = Qh; if isfield(P,'dbg') && isfield(P.dbg,'qTrue') && P.dbg.qTrue, Quse = pl.Q; end
    zp = zh - Ts*iPrev./(3600*Quse); v1p = a.*v1h + R1t.*(1-a)*iPrev;
    p11 = p11 + es.ekfQ(1,1); p12 = a.*p12; p22 = a.^2.*p22 + es.ekfQ(2,2);
    h = segSlope(min(max(floor(zp/0.1)+1,1),10));
    vhat = interp1(es.socBp, es.ocv, min(max(zp,0),1)) - v1p - R0t*im;
    inn = vm - vhat;
    Sv = h.^2.*p11 - 2*h.*p12 + p22 + es.ekfR;
    g1 = h.*p11 - p12; g2 = h.*p12 - p22; K1 = g1./Sv; K2 = g2./Sv;
    zh = zp + K1.*inn; v1h = v1p + K2.*inn;
    p11 = p11 - K1.*g1; p12 = p12 - K1.*g2; p22 = p22 - K2.*g2;
    % R0 RLS (differences)
    dv = vm - vPrev; di = im - iPrev; phi = -di;
    Kk = p0.*phi./(es.lambda0 + phi.^2.*p0);
    th0 = th0 + Kk.*(dv - phi.*th0); p0 = min((p0 - Kk.*phi.*p0)/es.lambda0, es.pMaxR0);
    zL0 = es.lambda0*zL0 + (1-es.lambda0)*zh; TL0 = es.lambda0*TL0 + (1-es.lambda0)*Tg;
    ok0 = p0 < es.infoR0;
    if any(ok0)
        [R0l,~,~,wl,idxl] = tabInterp(tab, es, zL0, TL0);
        [tab.r0, cnt(:,:,:,1)] = tabUpdate(tab.r0, cnt(:,:,:,1), wl, idxl, th0 - R0l, es.eta, ok0, es.c0R0, es.stepFloor);
    end
    % RC RLS at 1 s on 1 s averages
    if isfield(P,'dbg') && P.dbg.ocvTrue, zy = z; else, zy = zh; end
    r0y = R0t; if isfield(P,'dbg') && isfield(P.dbg,'r0True') && P.dbg.r0True, r0y = R0; end
    yBuf(mod(k-1,dec)+1,:) = interp1(es.socBp, es.ocv, min(max(zy,0),1)) - vm - r0y.*im; iBuf(mod(k-1,dec)+1) = im; ipBuf(mod(k-1,dec)+1) = iPrev; yPoint = yBuf(mod(k-1,dec)+1,:);
    if mod(k,dec) == 0
        yA = mean(yBuf,1); iA = mean(iBuf); h1 = mean(iBuf(1:dec/2)); h2 = mean(iBuf(dec/2+1:end));
        if startsWith(rcMode,'point'), yT = yPoint; else, yT = yA; end
        [~,~,tauc] = tabInterp(tab, es, zh, Tg);
        if ~isempty(yAvgPrev)
            useIV = isfield(es,'rcIV') && es.rcIV;
            [~,R1a,taua] = tabInterp(tab, es, zh, Tg); aa = exp(-P.TsRc./taua);
            xAux = aa.*xAuxPrev + R1a.*(1-aa)*mean(ipBuf);
            for g = 1:nG
                switch rcMode
                    case 'avg',   phiR = [yAvgPrev(g); 0.5*(iAvgPrev+h1); 1];
                    case 'avgold',phiR = [yAvgPrev(g); 0.5*(iAvgFull+iA); 1];
                    case 'point', phiR = [yPP(g); mean(ipBuf); 1];
                    case 'pointw'
                        al = exp(-Ts/tauc(g)); ww = al.^(dec-1:-1:0)'*(1-al)/(1-al^dec);
                        ord = mod((k-dec:k-1),dec)+1; phiR = [yPP(g); ww'*ipBuf(ord); 1];
                end
                zeta = phiR; if useIV, zeta(1) = xAuxPrev(g); end
                Pg = Prc(:,:,g); Kg = Pg*zeta/(es.lambdaRc + phiR'*Pg*zeta);
                thRc(:,g) = thRc(:,g) + Kg*(yT(g) - phiR'*thRc(:,g));
                Pg = (Pg - Kg*phiR'*Pg)/es.lambdaRc; tr_ = trace(Pg); if tr_ > es.pMaxRc, Pg = Pg*es.pMaxRc/tr_; end
                Prc(:,:,g) = Pg;
            end
            exc = es.lambdaExc*exc + (1-es.lambdaExc)*(iA - iAprevExc)^2;
            aE = thRc(1,:); okA = squeeze(Prc(1,1,:))' < es.infoRc & aE > es.aMin & aE < es.aMax & exc >= es.excMin;
            r1E = thRc(2,:)./(1-aE); tauE = -P.TsRc./log(min(max(aE,es.aMin),es.aMax));
            okA = okA & r1E > 0;
            zLrc = es.lambdaRc*zLrc + (1-es.lambdaRc)*zh; TLrc = es.lambdaRc*TLrc + (1-es.lambdaRc)*Tg;
            [~,R1c,tauc,wc,idxc] = tabInterp(tab, es, zLrc, TLrc);
            if any(okA)
                [tab.r1, cnt(:,:,:,2)] = tabUpdate(tab.r1, cnt(:,:,:,2), wc, idxc, r1E - R1c, es.eta*dec, okA, es.c0Rc, es.stepFloor);
                [tab.tau, cnt(:,:,:,3)] = tabUpdate(tab.tau, cnt(:,:,:,3), wc, idxc, tauE - tauc, es.eta*dec, okA, es.c0Rc, es.stepFloor);
            end
        else
            r1E = nan(1,nG); tauE = r1E;
        end
        yAvgPrev = yA; iAvgPrev = h2; iAvgFull = iA; yPP = yPoint; iAprevExc = iA; if exist('xAux','var'), xAuxPrev = xAux; end
    end
    % capacity
    Ah = Ah + im*Ts/3600;
    if abs(im) < es.restI, tRest = tRest + Ts; else, tRest = 0; restDone = false; end
    if tRest >= es.restT && ~restDone
        restDone = true;
        zO = interp1(es.ocv, es.socBp, vm, "linear", "extrap");
        if all(~isnan(zRestPrev))
            dz = zRestPrev - zO; use = abs(dz) >= es.capMinDz;
            S1(use) = es.capLambda*S1(use) + abs(Ah(use)); S2(use) = es.capLambda*S2(use) + abs(dz(use));
            Qh = S1./S2;
        end
        zRestPrev = zO; Ah(:) = 0;
    end
    vPrev = vm; iPrev = im;
    % ---- plant step to t+Ts (exact for constant i over the step) ----
    aT = exp(-Ts./tau);
    v1n = aT.*v1 + R1.*(1-aT)*i;
    Wh = Wh + abs(v*i)*Ts/3600;
    T = T + Ts*(i^2*R0 + v1.^2./R1 - (T - pl.tAmbC)./pl.Rth)./pl.Cth;
    z = z - Ts*i./(3600*pl.Q); v1 = v1n;
    % ---- log at 1 s ----
    if mod(k,dec) == 0
        li = li+1; L.t(li)=t+Ts; L.z(li,:)=z; L.zh(li,:)=zh; L.r0(li,:)=R0; L.r1(li,:)=R1; L.tau(li,:)=tau; L.Qh(li,:)=Qh;
        [L.r0t(li,:),L.r1t(li,:),L.taut(li,:)] = tabInterp(tab, es, zh, Tg); L.th0(li,:)=th0; L.r1rls(li,:)=r1E; L.taurls(li,:)=tauE;
        L.i(li)=i; L.v(li,:)=v; L.T(li,:)=T; L.Wh(li,:)=Wh; L.p0(li,:)=p0; L.paa(li,:)=squeeze(Prc(1,1,:))'; L.exc(li)=exc; L.mode(li)=mode;
    end
end
R.L = L; R.tab = tab; R.cnt = cnt; R.Qh = Qh;
end

function y = interpG(tab, pl, z, T)
persistent F key
k = {tab, pl.socBp, pl.tBpC};
if isempty(F) || ~isequal(key, k)
    F = containers.Map('KeyType','double','ValueType','any'); key = k;
end
h = sum(tab(:).*(1:numel(tab))');
if ~isKey(F, h), F(h) = griddedInterpolant({pl.socBp, pl.tBpC, 1:size(tab,3)}, tab, 'linear', 'nearest'); end
f = F(h);
y = f(min(max(z,0),1), min(max(T,pl.tBpC(1)),pl.tBpC(end)), 1:numel(z));
end

function [r0,r1,tau,wu,idx,w] = tabInterp(tab, es, z, T)
nG = numel(z); nS = numel(es.socBp); nT = numel(es.tBpC);
zc = min(max(z,es.socBp(1)),es.socBp(end)); Tc = min(max(T,es.tBpC(1)),es.tBpC(end));
js = min(floor((zc - es.socBp(1))/(es.socBp(2)-es.socBp(1))) + 1, nS-1);
jt = min(floor((Tc - es.tBpC(1))/(es.tBpC(2)-es.tBpC(1))) + 1, nT-1);
fs = (zc - es.socBp(js))./(es.socBp(2)-es.socBp(1)); ft = (Tc - es.tBpC(jt))./(es.tBpC(2)-es.tBpC(1));
off = (0:nG-1)*nS*nT;
idx = [js + (jt-1)*nS; js+1 + (jt-1)*nS; js + jt*nS; js+1 + jt*nS] + off;
w = [(1-fs).*(1-ft); fs.*(1-ft); (1-fs).*ft; fs.*ft];
if isfield(es,'nearFrac'), lo = double(fs <= es.nearFrac); hi = double(fs >= 1-es.nearFrac); else, lo = 1-fs; hi = fs; end
wu = [lo.*(1-ft); hi.*(1-ft); lo.*ft; hi.*ft];
r0 = sum(w.*tab.r0(idx),1); r1 = sum(w.*tab.r1(idx),1); tau = sum(w.*tab.tau(idx),1);
end

function [tb, c] = tabUpdate(tb, c, w, idx, err, eta, ok, c0, fl)
for g = find(ok)
    ii = idx(:,g); s = sign(err(g));
    tb(ii) = tb(ii) + eta*max(c0./(c0 + c(ii)), fl).*w(:,g).*tb(ii)*s;
    c(ii) = c(ii) + w(:,g);
end
end
