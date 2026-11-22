function report=test_BQ76952EVM_I2C_Simulink
%TEST_BQ76952EVM_I2C_SIMULINK Exercise the S-function transaction port in Simscape.
afe=fileparts(fileparts(mfilename('fullpath'))); td=fullfile(afe,'test');
mdl='BQ76952EVM_4S_test'; if bdIsLoaded(mdl), close_system(mdl,0); end
load_system(fullfile(td,[mdl '.slx']));
delete_line(mdl,'NoI2cTransaction/1','EVM/4');
delete_block([mdl '/NoI2cTransaction']);
add_block('simulink/Sources/From Workspace',[mdl '/IndependentI2cController'], ...
    'VariableName','i2cRequests','Interpolate','off','OutputAfterFinalValue','Holding final value', ...
    'Position',[70 735 190 765]);
add_line(mdl,'IndependentI2cController/1','EVM/4','autorouting','on');
add_block('simulink/Sinks/To Workspace',[mdl '/i2cResponseLog'], ...
    'VariableName','i2cResponseLog','SaveFormat','Timeseries','Position',[1030 430 1120 460]);
add_line(mdl,'EVM/4','i2cResponseLog/1','autorouting','on');

t=(0:0.01:0.29)'; q=zeros(numel(t),40,'uint8');
q(3,:)=packet(1,0,0x3E,uint8([1 0]),2);             % DEVICE_NUMBER pointer
q(4,:)=packet(2,1,0x40,uint8([]),2);                 % DEVICE_NUMBER read
q(5,:)=packet(3,1,0x14,uint8([]),2);                 % Cell 1 mV
q(6,:)=packet(4,1,0x3A,uint8([]),2);                 % Signed CC2 current
q(7,:)=packet(5,0,0x3E,uint8([0x90 0]),2);           % SET_CFGUPDATE
ptr=uint8([3 0x93]);
q(8,:)=packet(6,0,0x3E,ptr,2);                       % DA memory address
q(9,:)=packet(7,0,0x40,uint8(9),1);                   % change DA_CONFIG
checksum=uint8(255-mod(sum(double([ptr 9])),256));
q(10,:)=packet(8,0,0x60,uint8([checksum 5]),2);       % checksum + length
q(11,:)=packet(9,0,0x3E,ptr,2);
q(12,:)=packet(10,1,0x40,uint8([]),1);                % readback
q(13,:)=packet(11,0,0x3E,uint8([0x95 0]),2);          % ALL_FETS_OFF
assignin('base','i2cRequests',timeseries(q,t));
set_param(mdl,'SimulationCommand','update');
out=sim(mdl,'StopTime','0.30');
resp=out.i2cResponseLog; data=uint8(resp.Data);
if size(data,2)~=40 && size(data,1)==40, data=data.'; end
assert(size(data,2)==40,'Transaction response must be 40 bytes.');
assert(data(4,5)==0 && data(4,6)==2 && data(4,7)==0x95 && data(4,8)==0x76, ...
    'Device-number transaction did not return 0x7695 with ACK.');
cellRaw=double(data(5,7))+256*double(data(5,8));
assert(data(5,5)==0 && cellRaw==3700,'I2C Cell 1 register read was incorrect.');
currentRaw=double(data(6,7))+256*double(data(6,8));
if currentRaw>=32768, currentRaw=currentRaw-65536; end
assert(data(6,5)==0 && currentRaw<0,'I2C current read was not negative for discharge.');
assert(data(12,5)==0 && data(12,6)==1 && data(12,7)==9, ...
    'Data-memory transaction did not return the written DA_CONFIG byte.');
assert(out.chgLog.Data(end)<0.5 && out.dsgLog.Data(end)<0.5, ...
    'ALL_FETS_OFF subcommand did not interrupt the pack path.');
report=struct('passed',true,'deviceNumber',hex2dec('7695'), ...
    'cell1mV',cellRaw,'currentRaw',currentRaw,'daConfigReadback',data(12,7), ...
    'allFetsOff',true);
fprintf('PASS Simulink I2C port: device 0x7695; cell1 %d mV; current raw %d; DA_CONFIG %d; ALL_FETS_OFF.\n', ...
    cellRaw,currentRaw,data(12,7));
close_system(mdl,0);
end

function q=packet(seq,rd,reg,payload,n)
q=zeros(1,40,'uint8');
q(1:4)=typecast(uint32(seq),'uint8'); q(5)=8; q(6)=rd; q(7)=reg; q(8)=n;
if ~isempty(payload), q(9:8+numel(payload))=payload; end
end
