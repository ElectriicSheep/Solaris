function result=test_BQ76952EVM_16S
%TEST_BQ76952EVM_16S Run independent physical 16S harness.
afe=fileparts(fileparts(mfilename('fullpath'))); mdl='BQ76952EVM_16S_test';
load_system(fullfile(afe,'test',[mdl '.slx']));
set_param(mdl,'SimulationCommand','update'); out=sim(mdl,'StopTime','0.30');
ts=out.snapshotLog; snap=uint8(ts.Data);
if size(snap,2)~=144 && size(snap,1)==144, snap=snap.'; end
assert(size(snap,2)==144,'Snapshot signal must be 144 bytes per sample.');
keep=ts.Time>=0.05; snap=snap(keep,:);
addr=[hex2dec('14') hex2dec('16') hex2dec('30') hex2dec('32')];
v=cellfun(@(a)mean(readReg(snap,a))*1e-3,num2cell(addr));
stack=mean(readReg(snap,hex2dec('34')))*1e-2;
current=mean(readReg(snap,hex2dec('3A')))*1e-2;
assert(all(abs(v-3.7)<0.002),'16S sample cell voltages were not 3.700 V.');
assert(abs(stack-59.2)<0.04,'16S stack voltage was not approximately 59.2 V.');
assert(current < -1 && current > -3,'16S shunt current sign or magnitude was wrong.');
assert(out.chgLog.Data(end)>0.5 && out.dsgLog.Data(end)>0.5,'FETs should be on at nominal 16S.');
result=struct('passed',true,'sampledCellVolts',v,'stackVolts',stack,'chargePositiveCurrentA',current);
fprintf('PASS 16S: sampled cells %.3f %.3f %.3f %.3f V; stack %.3f V; current %.3f A.\n',v,stack,current);
end
function x=readReg(snap,a)
lo=double(snap(:,17+a)); hi=double(snap(:,18+a)); raw=lo+256*hi; x=raw-65536*(raw>=32768);
end
