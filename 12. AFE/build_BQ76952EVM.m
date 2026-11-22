function build_BQ76952EVM
%BUILD_BQ76952EVM Build the reusable, independent BQ76952EVM Simulink library.
% Run from any folder. The generated MEX is specific to the local MATLAB install.

afe = fileparts(mfilename('fullpath'));
repo = fileparts(afe);
addpath(afe);
emulator = fullfile(afe,'bq76952evmsfun');
if exist([emulator '.' mexext],'file') ~= 3 || newer(fullfile(afe,'bq76952_emul.c'),[emulator '.' mexext]) || ...
        newer(fullfile(afe,'bq76952evmsfun.c'),[emulator '.' mexext])
    mex('-R2018a','-outdir',afe,['-I' afe],['-I' fullfile(repo,'13. Pi','libresolar')], ...
        fullfile(afe,'bq76952evmsfun.c'),fullfile(afe,'bq76952_emul.c'));
end

libName = 'BQ76952EVM';
libFile = fullfile(afe,[libName '.slx']);
if bdIsLoaded(libName), close_system(libName,0); end
new_system(libName,'Library');
block = [libName '/BQ76952EVM'];
% Landscape block keeps the EVM photograph close to its natural aspect ratio;
% the 19 left-side conserving ports remain vertically ordered and stable.
add_block('built-in/Subsystem',block,'Position',[180 120 980 520]);
buildSubsystem(block);
makeMask(block,libName);
set_param(libName,'Lock','off');
save_system(libName,libFile);
fprintf('Built %s\n',libFile);
end

function buildSubsystem(sys)
% Simscape Connection Port supports left/right placement in this block;
% PACK therefore remains a stable right-side interface, beside its photo pin.
addConservingPort(sys,'PACK+',1,'Right',[300 25 330 55]);
addConservingPort(sys,'PACK-',2,'Right',[360 60 390 90]);
for k=16:-1:1
    y=55+29*(16-k);
    addConservingPort(sys,sprintf('CELL%d',k),19-k,'Left',[25 y 55 y+18]);
end
addConservingPort(sys,'BAT+',20,'Left',[25 555 55 585]);
addConservingPort(sys,'BAT-',21,'Left',[25 590 55 620]);

% EVM-style differential input filters and physical cell voltage sensors.
for k=0:16
    r=sprintf('RVC%02d',k); add_block('fl_lib/Electrical/Electrical Elements/Resistor',[sys '/' r], ...
        'R','CellSenseOhms','Position',[100 55+29*k 130 73+29*k]);
    if k==0, tap='BAT-'; else, tap=sprintf('CELL%d',k); end
    pwire(sys,[sys '/' tap],'port',[sys '/' r],'p');
end
for k=1:16
    y=65+29*(k-1);
    cap=sprintf('CVC%02d',k); vs=sprintf('VCell%02d',k); ps=sprintf('PSCell%02d',k);
    add_block('fl_lib/Electrical/Electrical Elements/Capacitor',[sys '/' cap], ...
        'C','CellFilterFarads','Position',[230 y 260 y+18]);
    add_block('fl_lib/Electrical/Electrical Sensors/Voltage Sensor',[sys '/' vs], ...
        'Position',[285 y 315 y+30]);
    add_block('nesl_utility/PS-Simulink Converter',[sys '/' ps], ...
        'Position',[340 y 385 y+25]);
    kLo=sprintf('%02d',k-1); kHi=sprintf('%02d',k);
    pwire(sys,[sys '/RVC' kHi],'n',[sys '/' cap],'p');
    pwire(sys,[sys '/RVC' kLo],'n',[sys '/' cap],'n');
    pwire(sys,[sys '/RVC' kHi],'n',[sys '/' vs],'p');
    pwire(sys,[sys '/RVC' kLo],'n',[sys '/' vs],'n');
    pwire(sys,[sys '/' vs],'V',[sys '/' ps],'input');
end

% Simulink signal ports for host writes and thermistor/die inputs.
add_block('simulink/Sources/In1',[sys '/hostWr'],'Port','1','PortDimensions','40', ...
    'OutDataTypeStr','uint8','Position',[25 570 55 590]);
add_block('simulink/Sources/In1',[sys '/tempPinsK'],'Port','2','PortDimensions','9', ...
    'OutDataTypeStr','double','Position',[25 610 55 630]);
add_block('simulink/Sources/In1',[sys '/tDieK'],'Port','3','PortDimensions','1', ...
    'OutDataTypeStr','double','Position',[25 650 55 670]);
add_block('simulink/Sources/In1',[sys '/i2cTxn'],'Port','4','PortDimensions','40', ...
    'OutDataTypeStr','uint8','Position',[25 690 55 710]);

% Current path: BAT- -> shunt -> anti-series CHG/DSG switches -> PACK-.
add_block('fl_lib/Electrical/Electrical Sensors/Current Sensor',[sys '/ShuntCurrentSensor'], ...
    'Position',[440 610 475 650]);
add_block('fl_lib/Electrical/Electrical Elements/Resistor',[sys '/CurrentShunt'], ...
    'R','ShuntOhms','Position',[500 615 535 645]);
add_block('ee_lib/Semiconductors & Converters/Ideal Semiconductor Switch',[sys '/CHG_FET'], ...
    'Ron','FetRon','Goff','FetGoff','Position',[565 585 605 625]);
add_block('ee_lib/Semiconductors & Converters/Ideal Semiconductor Switch',[sys '/DSG_FET'], ...
    'Ron','FetRon','Goff','FetGoff','Position',[635 630 675 670]);
pwire(sys,[sys '/BAT-'],'port',[sys '/ShuntCurrentSensor'],'p');
pwire(sys,[sys '/ShuntCurrentSensor'],'n',[sys '/CurrentShunt'],'p');
pwire(sys,[sys '/CurrentShunt'],'n',[sys '/CHG_FET'],'K');
pwire(sys,[sys '/CHG_FET'],'A',[sys '/DSG_FET'],'A');
pwire(sys,[sys '/DSG_FET'],'K',[sys '/PACK-'],'port');
add_block('fl_lib/Electrical/Electrical Elements/Resistor',[sys '/BoardPositiveLink'], ...
    'R','PositiveLinkOhms','Position',[455 520 490 550]);
pwire(sys,[sys '/BAT+'],'port',[sys '/BoardPositiveLink'],'p');
pwire(sys,[sys '/BoardPositiveLink'],'n',[sys '/PACK+'],'port');

% Terminal voltage sensors branch at internal component nodes so each exposed
% conserving terminal itself retains one unambiguous line connection.
add_block('fl_lib/Electrical/Electrical Sensors/Voltage Sensor',[sys '/VBATSensor'],'Position',[430 40 465 75]);
add_block('fl_lib/Electrical/Electrical Sensors/Voltage Sensor',[sys '/VPACKSensor'],'Position',[500 40 535 75]);
add_block('nesl_utility/PS-Simulink Converter',[sys '/PSVBAT'],'Position',[455 90 500 115]);
add_block('nesl_utility/PS-Simulink Converter',[sys '/PSVPACK'],'Position',[520 125 565 150]);
pwire(sys,[sys '/BoardPositiveLink'],'p',[sys '/VBATSensor'],'p');
pwire(sys,[sys '/ShuntCurrentSensor'],'p',[sys '/VBATSensor'],'n');
pwire(sys,[sys '/VBATSensor'],'V',[sys '/PSVBAT'],'input');
pwire(sys,[sys '/BoardPositiveLink'],'n',[sys '/VPACKSensor'],'p');
pwire(sys,[sys '/DSG_FET'],'K',[sys '/VPACKSensor'],'n');
pwire(sys,[sys '/VPACKSensor'],'V',[sys '/PSVPACK'],'input');

% Control signals for the two physical FET switch blocks.
add_block('nesl_utility/Simulink-PS Converter',[sys '/SPS_CHG'],'Position',[700 585 750 610]);
add_block('nesl_utility/Simulink-PS Converter',[sys '/SPS_DSG'],'Position',[700 630 750 655]);
pwire(sys,[sys '/SPS_CHG'],'output',[sys '/CHG_FET'],'G');
pwire(sys,[sys '/SPS_DSG'],'output',[sys '/DSG_FET'],'G');

% Sensor signal conditioning and vector assembly for the instance-local C state.
add_block('simulink/Signal Routing/Mux',[sys '/CellVoltageMux'],'Inputs','16','Position',[425 160 430 580]);
for k=1:16, add_line(sys,sprintf('PSCell%02d/1',k),sprintf('CellVoltageMux/%d',k),'autorouting','on'); end
add_block('nesl_utility/PS-Simulink Converter',[sys '/PSCurrent'],'Position',[495 680 545 705]);
add_block('simulink/Math Operations/Abs',[sys '/AbsCurrent'],'Position',[570 680 600 705]);
add_block('simulink/Logic and Bit Operations/Compare To Constant',[sys '/LoadRemoved'],'const','0.1','Position',[625 680 685 705]);
add_block('simulink/Signal Attributes/Data Type Conversion',[sys '/LoadRemovedDouble'], ...
    'OutDataTypeStr','double','Position',[700 680 755 705]);
add_block('simulink/Discrete/Unit Delay',[sys '/LoadRemovedDelay'], ...
    'SampleTime','SampleTime','InitialCondition','0','Position',[775 680 820 705]);
add_block('simulink/Signal Routing/Mux',[sys '/EmulatorInputMux'],'Inputs','9','Position',[690 390 695 660]);
add_block('simulink/Signal Attributes/Data Type Conversion',[sys '/HostWrDouble'], ...
    'OutDataTypeStr','double','Position',[90 570 145 595]);
add_block('simulink/Signal Attributes/Data Type Conversion',[sys '/I2cTxnDouble'], ...
    'OutDataTypeStr','double','Position',[90 690 145 715]);

% S-function parameters are local mask values; no Solaris buses/workspaces.
cfg='[SampleTime; UsedCellMask; round(ShuntOhms*1e6); DAConfig; ProtEnabledA; ProtEnabledB; MfgStatusInit; COV_Threshold; COV_Hyst; COV_Delay; CUV_Threshold; CUV_Hyst; CUV_Delay; OCC_Threshold; OCC_Delay; OCC_Recovery_mA; OCD1_Threshold; OCD1_Delay; OCD_Recovery_mA; SCD_Threshold; SCD_Delay; SCD_Recovery_s; OTC_Threshold_C; OTC_Recovery_C; OTD_Threshold_C; OTD_Recovery_C; UTC_Threshold_C; UTC_Recovery_C; UTD_Threshold_C; UTD_Recovery_C; OTUT_Delay_s; RecoveryTime_s; PinConfig(:); I2CAddress]';
add_block('simulink/User-Defined Functions/S-Function',[sys '/Emulator'], ...
    'FunctionName','bq76952evmsfun','Parameters',cfg,'Position',[770 380 865 520]);
add_block('simulink/Signal Routing/Demux',[sys '/OutputDemux'],'Outputs','[144 1 1 40]','Position',[890 400 895 610]);
add_block('simulink/Discrete/Unit Delay',[sys '/CHGFetDelay'], ...
    'SampleTime','SampleTime','InitialCondition','1','Position',[915 450 955 475]);
add_block('simulink/Discrete/Unit Delay',[sys '/DSGFetDelay'], ...
    'SampleTime','SampleTime','InitialCondition','1','Position',[915 500 955 525]);
add_block('simulink/Signal Attributes/Data Type Conversion',[sys '/SnapshotUint8'], ...
    'OutDataTypeStr','uint8','Position',[915 390 970 415]);
add_block('simulink/Signal Attributes/Data Type Conversion',[sys '/I2cRespUint8'], ...
    'OutDataTypeStr','uint8','Position',[915 595 970 620]);
add_line(sys,'CellVoltageMux/1','EmulatorInputMux/1','autorouting','on');
pwire(sys,[sys '/ShuntCurrentSensor'],'I',[sys '/PSCurrent'],'input');
add_line(sys,'PSCurrent/1','AbsCurrent/1','autorouting','on');
add_line(sys,'AbsCurrent/1','LoadRemoved/1','autorouting','on');
add_line(sys,'LoadRemoved/1','LoadRemovedDouble/1','autorouting','on');
add_line(sys,'LoadRemovedDouble/1','LoadRemovedDelay/1','autorouting','on');
add_line(sys,'PSCurrent/1','EmulatorInputMux/2','autorouting','on');
add_line(sys,'tempPinsK/1','EmulatorInputMux/3','autorouting','on');
add_line(sys,'tDieK/1','EmulatorInputMux/4','autorouting','on');
add_line(sys,'PSVBAT/1','EmulatorInputMux/5','autorouting','on');
add_line(sys,'PSVPACK/1','EmulatorInputMux/6','autorouting','on');
add_line(sys,'LoadRemovedDelay/1','EmulatorInputMux/7','autorouting','on');
add_line(sys,'hostWr/1','HostWrDouble/1','autorouting','on');
add_line(sys,'HostWrDouble/1','EmulatorInputMux/8','autorouting','on');
add_line(sys,'i2cTxn/1','I2cTxnDouble/1','autorouting','on');
add_line(sys,'I2cTxnDouble/1','EmulatorInputMux/9','autorouting','on');
add_line(sys,'EmulatorInputMux/1','Emulator/1','autorouting','on');
add_line(sys,'Emulator/1','OutputDemux/1','autorouting','on');
add_line(sys,'OutputDemux/1','SnapshotUint8/1','autorouting','on');
add_line(sys,'OutputDemux/2','CHGFetDelay/1','autorouting','on');
add_line(sys,'OutputDemux/3','DSGFetDelay/1','autorouting','on');
add_line(sys,'CHGFetDelay/1','SPS_CHG/1','autorouting','on');
add_line(sys,'DSGFetDelay/1','SPS_DSG/1','autorouting','on');

add_block('simulink/Sinks/Out1',[sys '/snapshot'],'Port','1','PortDimensions','144','OutDataTypeStr','uint8','Position',[935 400 965 420]);
add_block('simulink/Sinks/Out1',[sys '/chgFet'],'Port','2','PortDimensions','1','OutDataTypeStr','double','Position',[935 500 965 520]);
add_block('simulink/Sinks/Out1',[sys '/dsgFet'],'Port','3','PortDimensions','1','OutDataTypeStr','double','Position',[935 550 965 570]);
add_block('simulink/Sinks/Out1',[sys '/i2cResp'],'Port','4','PortDimensions','40','OutDataTypeStr','uint8','Position',[935 590 965 610]);
add_line(sys,'SnapshotUint8/1','snapshot/1','autorouting','on');
add_line(sys,'OutputDemux/2','chgFet/1','autorouting','on');
add_line(sys,'OutputDemux/3','dsgFet/1','autorouting','on');
add_line(sys,'OutputDemux/4','I2cRespUint8/1','autorouting','on');
add_line(sys,'I2cRespUint8/1','i2cResp/1','autorouting','on');
end

function addConservingPort(sys,name,n,side,pos)
add_block('nesl_utility/Connection Port',[sys '/' name], ...
    'Port',num2str(n),'Side',side,'Position',pos);
end

function pwire(sys,a,pa,b,pb)
simscape.addConnection(a,pa,b,pb,'autorouting','on');
end

function makeMask(block,libName)
m=Simulink.Mask.create(block); m.Type='BQ76952EVM';
m.Description='Standalone behavioral BQ76952EVM. Conserving terminals retain fixed VC0-VC16 identities; use explicit external shorts for unused taps. J17 is available only through the transaction-level software interface.';
tabs=m.addDialogControl('tabcontainer','evmTabs');
tabNames={'BatteryCells','Current','Acquisition','Protection','FETs','Communications'};
tabPrompts={'Battery / cell configuration','Current sensing','Voltage and temperature acquisition','Protection thresholds and recovery','FET behaviour','Communications and diagnostics'};
for k=1:numel(tabNames), t=tabs.addDialogControl('tab',tabNames{k}); t.Prompt=tabPrompts{k}; end
seriesOptions=arrayfun(@(n)sprintf('%d',n),3:16,'UniformOutput',false);
addP(m,'popup','SeriesCount','Number of Series Cells','16',seriesOptions,'BatteryCells');
addP(m,'edit','UsedCellMask','Active VCell Mode (decimal)','65535',{},'BatteryCells');
addP(m,'edit','CellSenseOhms','VC series resistor (ohm)','20',{},'BatteryCells');
addP(m,'edit','CellFilterFarads','VC filter capacitor (F)','220e-9',{},'BatteryCells');
addP(m,'edit','PositiveLinkOhms','BAT+ to PACK+ path resistance (ohm)','1e-6',{},'BatteryCells');
addP(m,'popup','Preset','Configuration preset','Generic 16S',{'Generic 16S','Solaris 13S','Generic 4S'},'BatteryCells');
addP(m,'edit','ShuntOhms','Physical shunt resistance (ohm)','0.001',{},'Current');
addP(m,'edit','DAConfig','DA_CONFIG data-memory byte','6',{},'Current');
addP(m,'edit','SampleTime','Emulator sample time (s)','0.01',{},'Acquisition');
addP(m,'edit','PinConfig','Nine pin-configuration bytes','[7 7 0 7 0 7 7 7 7]',{},'Acquisition');
addP(m,'edit','ProtEnabledA','Protection enable A byte','188',{},'Protection');
addP(m,'edit','ProtEnabledB','Protection enable B byte','51',{},'Protection');
addP(m,'edit','COV_Threshold','COV threshold (50.6 mV units)','84',{},'Protection');
addP(m,'edit','COV_Hyst','COV recovery hysteresis (50.6 mV units)','2',{},'Protection');
addP(m,'edit','COV_Delay','COV delay (3.3 ms units)','74',{},'Protection');
addP(m,'edit','CUV_Threshold','CUV threshold (50.6 mV units)','53',{},'Protection');
addP(m,'edit','CUV_Hyst','CUV recovery hysteresis (50.6 mV units)','2',{},'Protection');
addP(m,'edit','CUV_Delay','CUV delay (3.3 ms units)','74',{},'Protection');
addP(m,'edit','OCC_Threshold','OCC threshold (2 mV per shunt)','7',{},'Protection');
addP(m,'edit','OCC_Delay','OCC delay code','4',{},'Protection');
addP(m,'edit','OCC_Recovery_mA','OCC recovery current (mA)','-200',{},'Protection');
addP(m,'edit','OCD1_Threshold','OCD1 threshold (2 mV per shunt)','28',{},'Protection');
addP(m,'edit','OCD1_Delay','OCD1 delay code','127',{},'Protection');
addP(m,'edit','OCD_Recovery_mA','OCD recovery threshold (mA)','200',{},'Protection');
addP(m,'edit','SCD_Threshold','SCD threshold code','5',{},'Protection');
addP(m,'edit','SCD_Delay','SCD delay code','2',{},'Protection');
addP(m,'edit','SCD_Recovery_s','SCD recovery time (s)','5',{},'Protection');
addP(m,'edit','OTC_Threshold_C','OTC threshold (degC)','45',{},'Protection');
addP(m,'edit','OTC_Recovery_C','OTC recovery (degC)','40',{},'Protection');
addP(m,'edit','OTD_Threshold_C','OTD threshold (degC)','60',{},'Protection');
addP(m,'edit','OTD_Recovery_C','OTD recovery (degC)','55',{},'Protection');
addP(m,'edit','UTC_Threshold_C','UTC threshold (degC)','0',{},'Protection');
addP(m,'edit','UTC_Recovery_C','UTC recovery (degC)','5',{},'Protection');
addP(m,'edit','UTD_Threshold_C','UTD threshold (degC)','-10',{},'Protection');
addP(m,'edit','UTD_Recovery_C','UTD recovery (degC)','-5',{},'Protection');
addP(m,'edit','OTUT_Delay_s','OT/UT delay (s)','2',{},'Protection');
addP(m,'edit','RecoveryTime_s','Recovery time (s)','3',{},'Protection');
addP(m,'edit','MfgStatusInit','Manufacturing status initial word','16',{},'FETs');
addP(m,'edit','FetRon','Physical switch on resistance (ohm)','0.001',{},'FETs');
addP(m,'edit','FetGoff','Physical switch off conductance (S)','1e-6',{},'FETs');
addP(m,'popup','DisplayMode','Display Mode','Schematic View', ...
    {'PCB View','Schematic View'},'Communications');
addP(m,'edit','I2CAddress','J17 I2C 7-bit address','8',{},'Communications');
note=m.getDialogControl('evmTabs').getDialogControl('Communications').addDialogControl('text','ProtocolNote');
note.Prompt='J17 software transaction interface: i2cTxn (40-byte request) / i2cResp (40-byte response); supports device address, ACK/NACK, direct registers, data memory and implemented subcommands. This is not an electrical SDA/SCL waveform model. J22 SPI/HDQ is not implemented as a functional interface.';
% Put each parameter inside its tab and hide the default Parameters group.
m.removeDialogControl('ParameterGroupVar');
p=m.getParameter('Preset');
p.Callback=['switch get_param(gcb,''Preset''), ' ...
    'case ''Solaris 13S'', set_param(gcb,''SeriesCount'',''13''); set_param(gcb,''UsedCellMask'',''36863''); ' ...
    'set_param(gcb,''DAConfig'',''6''); set_param(gcb,''ShuntOhms'',''0.001''); ' ...
    'case ''Generic 4S'', set_param(gcb,''SeriesCount'',''4''); set_param(gcb,''UsedCellMask'',''32775''); ' ...
    'case ''Generic 16S'', set_param(gcb,''SeriesCount'',''16''); set_param(gcb,''UsedCellMask'',''65535''); end'];
p=m.getParameter('SeriesCount');
p.Callback=['n=str2double(get_param(gcb,''SeriesCount'')); ' ...
    'v=uint16(2^(n-1)-1+32768); if n==16, v=65535; end; ' ...
    'set_param(gcb,''UsedCellMask'',num2str(double(v)))'];
% Port labels name the real external ports.  The LConn/RConn indices are
% derived from addConservingPort's stable port numbers; signal port indices
% match the actual Inport/Outport blocks in build_BQ76952EVM.
portLabels={};
for n=1:16, portLabels{end+1}=sprintf('port_label(''lconn'',%d,''CELL%d'');',n,17-n); end %#ok<AGROW>
portLabels{end+1}='port_label(''lconn'',17,''BAT+'');';
portLabels{end+1}='port_label(''lconn'',18,''BAT-'');';
portLabels{end+1}='port_label(''rconn'',1,''PACK+'');';
portLabels{end+1}='port_label(''rconn'',2,''PACK-'');';
signalLabels={ ...
    'port_label(''input'',1,''SIM hostWr'');', ...
    'port_label(''input'',2,''SIM tempPinsK'');', ...
    'port_label(''input'',3,''SIM tDieK'');', ...
    'port_label(''input'',4,''I2C transaction request (SW)'');', ...
    'port_label(''output'',1,''SIM snapshot'');', ...
    'port_label(''output'',2,''SIM chgFet status'');', ...
    'port_label(''output'',3,''SIM dsgFet status'');', ...
    'port_label(''output'',4,''I2C transaction response (SW)'');'};
pcbIcon={ ...
    'color(''white''); patch([0 1 1 0],[0 0 1 1],[1 1 1]);', ...
    sprintf('image(imread(fullfile(fileparts(which(''%s'')),''assets'',''bq76952evm_top_cropped.png'')),[0.18 0.0125 0.64 0.975]);',libName)};
schematicIcon={ ...
    'color(''white''); patch([0.14 0.86 0.86 0.14],[0.01 0.01 0.99 0.99],[1 1 1]);', ...
    'color(''black''); plot([0.14 0.86 0.86 0.14 0.14],[0.01 0.01 0.99 0.99 0.01]);', ...
    'text(0.5,0.965,''{\bf BQ76952EVM}'',''horizontalAlignment'',''center'',''texmode'',''on'');', ...
    'text(0.5,0.925,''16-Cell Battery Monitor & Protector'',''horizontalAlignment'',''center'');', ...
    'color(''black''); text(0.20,0.875,''{\bf BATTERY SENSING}'',''horizontalAlignment'',''center'',''texmode'',''on'');', ...
    'text(0.50,0.875,''{\bf PACK POWER}'',''horizontalAlignment'',''center'',''texmode'',''on'');', ...
    'text(0.80,0.875,''{\bf SOFTWARE / DIAGNOSTICS}'',''horizontalAlignment'',''center'',''texmode'',''on'');', ...
    'color(''cyan''); plot([0.04 0.96],[0.85 0.85]);', ...
    'color(''white''); patch([0.18 0.82 0.82 0.18],[0.32 0.32 0.70 0.70],[0.92 0.94 0.95]);', ...
    'color(''black''); text(0.5,0.61,''{\bf BQ76952}'',''horizontalAlignment'',''center'',''texmode'',''on'');', ...
    'text(0.5,0.54,''J17 EXT_I2C: 1 SDA | 2 SCL | 3 unlabeled | 4 PGND'',''horizontalAlignment'',''center'');', ...
    'text(0.5,0.49,''J22 EXT_SPI / HDQ: 1 PACK- | 2 SPI_CS | 3 SPI_CLK | 4 SPI_MISO | 5 SPI_MOSI / HDQ'',''horizontalAlignment'',''center'');', ...
    'text(0.5,0.44,''J17 EXT_I2C is a software transaction abstraction; no electrical SDA/SCL pins'',''horizontalAlignment'',''center'');', ...
    'text(0.5,0.405,''i2cTxn / i2cResp are software-only; J22 SPI / HDQ is not modeled'',''horizontalAlignment'',''center'');', ...
    'text(0.5,0.355,''CELLx tap terminals feed the corresponding IC VCx differential inputs'',''horizontalAlignment'',''center'');', ...
    'text(0.5,0.33,''SIM ports: hostWr, tempPinsK, tDieK, snapshot, chgFet, dsgFet'',''horizontalAlignment'',''center'');', ...
    'color(''cyan''); plot([0.08 0.92],[0.27 0.27]);', ...
    'color(''black''); text(0.5,0.22,''{\bf No hardware serial pins modeled}'',''horizontalAlignment'',''center'',''texmode'',''on'');'};
% Popup parameters evaluate to their 1-based choice index in the icon
% workspace (PCB View=1, Schematic View=2).
modeExpr=sprintf('if DisplayMode == 1, %s else, %s end', ...
    strjoin([pcbIcon portLabels signalLabels],' '), ...
    strjoin(schematicIcon,' '));
m.Display=modeExpr;
m.IconUnits='normalized'; m.IconFrame='off'; m.IconOpaque='off'; m.RunInitForIconRedraw='on';
m.IconRotate='none'; m.PortRotate='default';
end

function addP(m,type,name,prompt,value,options,container)
p=m.addParameter('Type',type,'Name',name,'Prompt',prompt);
p.Container=container;
if ~isempty(options), p.TypeOptions=options; end
p.Value=value;
end

function tf=newer(src,dst)
tf=false;
if exist(dst,'file')~=3 || exist(src,'file')~=2, tf=true; return; end
a=dir(src); b=dir(dst); tf=a.datenum>b.datenum;
end
