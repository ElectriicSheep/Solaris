function report=test_BQ76952EVM_DisplayModes
%TEST_BQ76952EVM_DISPLAYMODES Prove view switching keeps interfaces and results.
afe=fileparts(fileparts(mfilename('fullpath')));
testDir=fullfile(afe,'test'); addpath(afe,testDir);
modes={'PCB View','Schematic View','PCB View','Schematic View'};
models={'BQ76952EVM_4S_test','BQ76952EVM_13S_test'};
testFns={@test_BQ76952EVM_4S,@test_BQ76952EVM_13S};
report=struct;
for j=1:numel(models)
    mdl=models{j};
    if bdIsLoaded(mdl), close_system(mdl,0); end
    load_system(fullfile(testDir,[mdl '.slx']));
    evm=[mdl '/EVM']; sf=[evm '/Emulator'];
    signature0=interfaceSignature(evm);
    config0=get_param(sf,'Parameters');
    values0=get_param(evm,'MaskValues');
    maskNames=get_param(evm,'MaskNames');
    displayIdx=find(strcmp(maskNames,'DisplayMode'),1);
    nonDisplayIdx=setdiff(1:numel(maskNames),displayIdx);
    results=cell(size(modes));
    for k=1:numel(modes)
        set_param(evm,'DisplayMode',modes{k});
        set_param(mdl,'SimulationCommand','update');
        assert(isequal(interfaceSignature(evm),signature0), ...
            'Display switching changed external port names or counts.');
        assert(strcmp(get_param(sf,'Parameters'),config0), ...
            'Display switching changed the C emulator configuration.');
        values=get_param(evm,'MaskValues');
        assert(isequal(values(nonDisplayIdx),values0(nonDisplayIdx)), ...
            'A non-display mask setting changed while switching views.');
        results{k}=testFns{j}();
    end
    for k=2:numel(results)
        assert(abs(results{k}.stackVolts-results{1}.stackVolts)<1e-9);
        assert(abs(results{k}.chargePositiveCurrentA-results{1}.chargePositiveCurrentA)<1e-9);
        assert(max(abs(results{k}.usedCellVolts-results{1}.usedCellVolts))<1e-9);
    end
    report.(mdl)=struct('modes',{modes},'portSignature',signature0, ...
        'sFunctionParametersStable',true,'nominalResultsStable',true);
    fprintf('PASS %s: four view changes; interface, emulator settings and nominal outputs unchanged.\n',mdl);
end
end

function s=interfaceSignature(block)
ph=get_param(block,'PortHandles');
counts=[numel(ph.Inport),numel(ph.Outport),numel(ph.LConn),numel(ph.RConn)];
p=simscape.connectionPortProperties(block);
names=sort(string({p.Name}));
s=struct('signalPortCounts',counts,'physicalPortNames',names);
end
