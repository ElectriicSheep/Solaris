function build_BQ76952EVM_16S_test
%BUILD_BQ76952EVM_16S_TEST Build an independent 16S Simscape harness.
afe=fileparts(fileparts(mfilename('fullpath'))); addpath(afe);
load_system(fullfile(afe,'BQ76952EVM.slx'));
mdl='BQ76952EVM_16S_test'; if bdIsLoaded(mdl), close_system(mdl,0); end
new_system(mdl);
set_param(mdl,'StopTime','0.30','SolverType','Variable-step','Solver','ode23t', ...
    'MaxStep','0.002','SignalLogging','on','SignalLoggingName','logsout', ...
    'ReturnWorkspaceOutputs','on');
evm=[mdl '/EVM'];
add_block('BQ76952EVM/BQ76952EVM',evm,'Position',[640 170 900 550]);
set_param(evm,'SeriesCount','16','UsedCellMask','65535','Preset','Generic 16S', ...
    'SampleTime','0.01','ShuntOhms','0.001');
for k=1:16
    name=sprintf('VC%02d',k); src=[mdl '/' name];
    add_block('fl_lib/Electrical/Electrical Sources/DC Voltage Source',src, ...
        'v0','3.7','Position',[80+95*mod(k-1,8) 90+130*floor((k-1)/8) 120+95*mod(k-1,8) 125+130*floor((k-1)/8)]);
    if k==1, lo='BAT-'; else, lo=sprintf('CELL%d',k-1); end
    simscape.addConnection(src,'n',evm,lo,'autorouting','on');
    simscape.addConnection(src,'p',evm,sprintf('CELL%d',k),'autorouting','on');
end
add_block('fl_lib/Electrical/Electrical Sources/DC Voltage Source',[mdl '/BATplusTie'], ...
    'v0','0','Position',[350 90 390 125]);
simscape.addConnection([mdl '/BATplusTie'],'n',evm,'CELL16','autorouting','on');
simscape.addConnection([mdl '/BATplusTie'],'p',evm,'BAT+','autorouting','on');
add_block('fl_lib/Electrical/Electrical Elements/Resistor',[mdl '/PackLoad'], ...
    'R','30','Position',[420 450 460 490]);
simscape.addConnection(evm,'PACK+',[mdl '/PackLoad'],'p','autorouting','on');
simscape.addConnection([mdl '/PackLoad'],'n',evm,'PACK-','autorouting','on');
add_block('fl_lib/Electrical/Electrical Elements/Electrical Reference',[mdl '/ElectricalReference'], ...
    'Position',[80 480 110 510]);
simscape.addConnection([mdl '/ElectricalReference'],'V',[mdl '/VC01'],'n','autorouting','on');
add_block('nesl_utility/Solver Configuration',[mdl '/SolverConfiguration'], ...
    'Position',[130 480 175 515]);
simscape.addConnection([mdl '/SolverConfiguration'],'port',[mdl '/VC01'],'n','autorouting','on');
add_block('simulink/Sources/Constant',[mdl '/NoHostWrite'],'Value','zeros(40,1,''uint8'')');
add_block('simulink/Sources/Constant',[mdl '/RoomTemperaturePins'],'Value','298.15*ones(9,1)');
add_block('simulink/Sources/Constant',[mdl '/RoomTemperatureDie'],'Value','298.15');
add_block('simulink/Sources/Constant',[mdl '/NoI2cTransaction'],'Value','zeros(40,1,''uint8'')');
add_line(mdl,'NoHostWrite/1','EVM/1'); add_line(mdl,'RoomTemperaturePins/1','EVM/2');
add_line(mdl,'RoomTemperatureDie/1','EVM/3'); add_line(mdl,'NoI2cTransaction/1','EVM/4');
add_block('simulink/Sinks/To Workspace',[mdl '/snapshotLog'],'VariableName','snapshotLog','SaveFormat','Timeseries');
add_block('simulink/Sinks/To Workspace',[mdl '/chgLog'],'VariableName','chgLog','SaveFormat','Timeseries');
add_block('simulink/Sinks/To Workspace',[mdl '/dsgLog'],'VariableName','dsgLog','SaveFormat','Timeseries');
add_line(mdl,'EVM/1','snapshotLog/1'); add_line(mdl,'EVM/2','chgLog/1'); add_line(mdl,'EVM/3','dsgLog/1');
save_system(mdl,fullfile(afe,'test',[mdl '.slx']));
set_param(mdl,'SimulationCommand','update');
fprintf('Updated independent 16S harness %s\n',fullfile(afe,'test',[mdl '.slx']));
end
