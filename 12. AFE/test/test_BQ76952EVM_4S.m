function result=test_BQ76952EVM_4S
%TEST_BQ76952EVM_4S Compile/run the independent physical 4S EVM harness.
afe=fileparts(fileparts(mfilename('fullpath')));
mdl='BQ76952EVM_4S_test';
load_system(fullfile(afe,'test',[mdl '.slx']));
set_param(mdl,'SimulationCommand','update');
out=sim(mdl,'StopTime','0.30');
ts=out.snapshotLog;
snap=uint8(ts.Data);
if size(snap,2)~=144 && size(snap,1)==144, snap=snap.'; end
assert(size(snap,2)==144,'Snapshot signal must be 144 bytes per sample.');
assert(all(snap(:,1)==uint8('B')) && all(snap(:,2)==uint8('Q')) && ...
    all(snap(:,3)==uint8('7')) && all(snap(:,4)==uint8('6')), ...
    'Emulator snapshot header is invalid.');
keep=ts.Time>=0.05;
assert(any(keep),'No post-startup samples recorded.');
snap=snap(keep,:);
v=[readReg(snap,hex2dec('14')) readReg(snap,hex2dec('16')) ...
   readReg(snap,hex2dec('18')) readReg(snap,hex2dec('32'))];
vMean=mean(v,1)*1e-3;
vStack=mean(readReg(snap,hex2dec('34')))*1e-2;
current=mean(readReg(snap,hex2dec('3A')))*1e-2; % charge-positive
chg=out.chgLog.Data(:); dsg=out.dsgLog.Data(:);
assert(all(abs(vMean-3.7)<0.002),'4S used cell channels did not report 3.700 V.');
assert(abs(vStack-14.8)<0.02,'Stack voltage was not approximately 14.8 V.');
assert(current < -1 && current > -5,'Discharge shunt current sign or magnitude is wrong.');
assert(all(chg(end-3:end)>0.5) && all(dsg(end-3:end)>0.5),'FETs did not remain enabled at nominal 4S.');
result=struct('passed',true,'usedCellVolts',vMean,'stackVolts',vStack, ...
    'chargePositiveCurrentA',current,'chgFet',chg,'dsgFet',dsg, ...
    'samples',size(snap,1));
fprintf('PASS 4S: cells %.3f %.3f %.3f %.3f V; stack %.3f V; charge-positive current %.3f A; %d snapshots.\n', ...
    vMean(1),vMean(2),vMean(3),vMean(4),vStack,current,result.samples);
end

function value=readReg(snap,address)
lo=double(snap(:,17+address)); hi=double(snap(:,18+address));
raw=lo+256*hi; value=raw-65536*(raw>=32768);
end
