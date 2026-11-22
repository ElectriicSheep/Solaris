function build_BQ76952EVM_4S_test
%BUILD_BQ76952EVM_4S_TEST Build an independent 4S Simscape electrical harness.
afe=fileparts(fileparts(mfilename('fullpath')));
libFile=fullfile(afe,'BQ76952EVM.slx');
addpath(afe); load_system(libFile);
mdl='BQ76952EVM_4S_test';
if bdIsLoaded(mdl), close_system(mdl,0); end
new_system(mdl);
set_param(mdl,'StopTime','0.30','SolverType','Variable-step','Solver','ode23t', ...
    'MaxStep','0.002','SignalLogging','on','SignalLoggingName','logsout', ...
    'ReturnWorkspaceOutputs','on');

evm=[mdl '/EVM'];
add_block('BQ76952EVM/BQ76952EVM',evm,'Position',[640 170 900 550]);
set_param(evm,'SeriesCount','4','UsedCellMask','32775','Preset','Generic 4S', ...
    'SampleTime','0.01','ShuntOhms','0.001');

% Actual cells 1, 2, 3, and 16 are used. VC4-VC15 are explicitly shorted
% by zero-volt sources, retaining the mandatory bottom and top measurements.
for k=1:16
    name=sprintf('VC%02d',k);
    src=[mdl '/' name];
    add_block('fl_lib/Electrical/Electrical Sources/DC Voltage Source',src, ...
        'v0',voltageForChannel(k),'Position',[80+95*mod(k-1,8) 90+130*floor((k-1)/8) 120+95*mod(k-1,8) 125+130*floor((k-1)/8)]);
    if k==1, lo='BAT-'; else, lo=sprintf('CELL%d',k-1); end
    simscape.addConnection(src,'n',evm,lo,'autorouting','on');
    simscape.addConnection(src,'p',evm,sprintf('CELL%d',k),'autorouting','on');
end

% BAT- is also the IC VC0 reference internally; BAT+ and CELL16 are tied
% externally to the actual top battery node in this independent harness.
add_block('fl_lib/Electrical/Electrical Sources/DC Voltage Source',[mdl '/BATplusTie'], ...
    'v0','0','Position',[350 90 390 125]);
simscape.addConnection([mdl '/BATplusTie'],'n',evm,'CELL16','autorouting','on');
simscape.addConnection([mdl '/BATplusTie'],'p',evm,'BAT+','autorouting','on');
add_block('fl_lib/Electrical/Electrical Elements/Resistor',[mdl '/PackLoad'], ...
    'R','5','Position',[420 450 460 490]);
simscape.addConnection(evm,'PACK+',[mdl '/PackLoad'],'p','autorouting','on');
simscape.addConnection([mdl '/PackLoad'],'n',evm,'PACK-','autorouting','on');

add_block('fl_lib/Electrical/Electrical Elements/Electrical Reference',[mdl '/ElectricalReference'], ...
    'Position',[80 480 110 510]);
simscape.addConnection([mdl '/ElectricalReference'],'V',[mdl '/VC01'],'n','autorouting','on');
add_block('nesl_utility/Solver Configuration',[mdl '/SolverConfiguration'], ...
    'Position',[130 480 175 515]);
simscape.addConnection([mdl '/SolverConfiguration'],'port',[mdl '/VC01'],'n','autorouting','on');

add_block('simulink/Sources/Constant',[mdl '/NoHostWrite'],'Value','zeros(40,1,''uint8'')', ...
    'Position',[80 585 150 610]);
add_block('simulink/Sources/Constant',[mdl '/RoomTemperaturePins'],'Value','298.15*ones(9,1)', ...
    'Position',[80 635 150 660]);
add_block('simulink/Sources/Constant',[mdl '/RoomTemperatureDie'],'Value','298.15', ...
    'Position',[80 685 150 710]);
add_block('simulink/Sources/Constant',[mdl '/NoI2cTransaction'],'Value','zeros(40,1,''uint8'')', ...
    'Position',[80 735 150 760]);
add_line(mdl,'NoHostWrite/1','EVM/1','autorouting','on');
add_line(mdl,'RoomTemperaturePins/1','EVM/2','autorouting','on');
add_line(mdl,'RoomTemperatureDie/1','EVM/3','autorouting','on');
add_line(mdl,'NoI2cTransaction/1','EVM/4','autorouting','on');

add_block('simulink/Sinks/To Workspace',[mdl '/snapshotLog'],'VariableName','snapshotLog', ...
    'SaveFormat','Timeseries','Position',[1030 200 1100 230]);
add_block('simulink/Sinks/To Workspace',[mdl '/chgLog'],'VariableName','chgLog', ...
    'SaveFormat','Timeseries','Position',[1030 280 1100 310]);
add_block('simulink/Sinks/To Workspace',[mdl '/dsgLog'],'VariableName','dsgLog', ...
    'SaveFormat','Timeseries','Position',[1030 360 1100 390]);
add_line(mdl,'EVM/1','snapshotLog/1','autorouting','on');
add_line(mdl,'EVM/2','chgLog/1','autorouting','on');
add_line(mdl,'EVM/3','dsgLog/1','autorouting','on');

save_system(mdl,fullfile(afe,'test',[mdl '.slx']));
set_param(mdl,'SimulationCommand','update');
fprintf('Updated and saved independent harness %s\n',fullfile(afe,'test',[mdl '.slx']));
end

function v=voltageForChannel(k)
if ismember(k,[1 2 3 16]), v='3.7'; else, v='0'; end
end
