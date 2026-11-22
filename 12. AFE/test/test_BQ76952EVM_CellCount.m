function report=test_BQ76952EVM_CellCount
%TEST_BQ76952EVM_CELLCOUNT Verify count-derived VCell Mode and stable ports.
afe=fileparts(fileparts(mfilename('fullpath'))); td=fullfile(afe,'test'); addpath(afe);
mdl='BQ76952EVM_4S_test'; if bdIsLoaded(mdl), close_system(mdl,0); end
load_system(fullfile(td,[mdl '.slx'])); evm=[mdl '/EVM'];
expected=containers.Map({3,4,13,16},{32771,32775,36863,65535});
signature=portSignature(evm); values=4;
for n=[3 4 13 16]
    set_param(evm,'SeriesCount',num2str(n));
    mask=double(str2double(get_param(evm,'UsedCellMask')));
    assert(mask==expected(n),'Cell count did not set the required bottom/top VCell Mode mask.');
    assert(isequal(portSignature(evm),signature), ...
        'The fixed linked-library conserving interface unexpectedly changed.');
    values(end+1)=mask; %#ok<AGROW>
end
% Two library instances retain independent settings while preserving the same
% physical terminal identities. This is a parameter-isolation check only.
evm2=[mdl '/EVM2'];
add_block('BQ76952EVM/BQ76952EVM',evm2,'Position',[1040 170 1840 570]);
set_param(evm,'SeriesCount','4'); set_param(evm2,'SeriesCount','13');
assert(strcmp(get_param(evm,'UsedCellMask'),'32775'));
assert(strcmp(get_param(evm2,'UsedCellMask'),'36863'));
assert(isequal(portSignature(evm),portSignature(evm2)));
fprintf(['PASS count configuration 3S/4S/13S/16S VCell Mode and two-instance ' ...
    'mask isolation. Conserving port count intentionally remains fixed for safety.\n']);
report=struct('passed',true,'testedCounts',[3 4 13 16], ...
    'usedCellMasks',[32771 32775 36863 65535], ...
    'fixedPhysicalPortSignature',signature,'dynamicPhysicalPortCount',false);
close_system(mdl,0);
end

function s=portSignature(block)
h=get_param(block,'PortHandles'); p=simscape.connectionPortProperties(block);
s=struct('signal',[numel(h.Inport) numel(h.Outport)], ...
    'conserving',[numel(h.LConn) numel(h.RConn)],'names',sort(string({p.Name})));
end
