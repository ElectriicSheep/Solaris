function export_BQ76952EVM_views
%EXPORT_BQ76952EVM_VIEWS Export the actual masked library block in both modes.
afe=fileparts(fileparts(mfilename('fullpath')));
addpath(afe);
load_system(fullfile(afe,'BQ76952EVM.slx'));
mdl='BQ76952EVM_view_export';
if bdIsLoaded(mdl), close_system(mdl,0); end
new_system(mdl);
set_param(mdl,'PaperOrientation','landscape','PaperPositionMode','auto');
blk=[mdl '/BQ76952EVM'];
add_block('BQ76952EVM/BQ76952EVM',blk,'Position',[550 250 1350 650]);
open_system(mdl);
% Leave a gutter around the system canvas so outer Simulink port labels are
% included in the exported image. Higher output DPI retains readable text.
set_param(blk,'DisplayMode','PCB View'); set_param(mdl,'ZoomFactor','55'); drawnow;
print(['-s' mdl],'-dpng','-r180',fullfile(afe,'test','BQ76952EVM_PCB_View.png'));
set_param(blk,'DisplayMode','Schematic View'); set_param(mdl,'ZoomFactor','55'); drawnow;
print(['-s' mdl],'-dpng','-r180',fullfile(afe,'test','BQ76952EVM_Schematic_View.png'));
close_system(mdl,0);
fprintf('Exported PCB and schematic view images under %s\n',fullfile(afe,'test'));
end
