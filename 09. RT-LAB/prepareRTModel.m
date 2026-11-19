function prepareRTModel(rtModelFile)
%PREPARERTMODEL Make an RT-LAB imported copy of bmsTestPlatform buildable.
%   prepareRTModel(rtModelFile) edits the COPY at rtModelFile (the file RT-LAB
%   imported into its workspace), never the repo model. Run it with the
%   modularBMS project open, after every (re-)import:
%
%     prepareRTModel("C:\Users\scb4\OPAL-RT\RT-LABv2026.1_Workspace\<project>\models\bmsTestPlatform\bmsTestPlatform.slx")
%
%   Changes made to the copy:
%     1. Configuration: the reference to cfgHarness (data dictionary) is replaced
%        by a local copy named cfgRT, because RT-LAB's model separation fails on a
%        configuration reference ("Index exceeds array bounds", RT-LAB v2026.1).
%        Solver settings are copied unchanged (fixed-step ode1, 10 ms, tunable);
%        only the run settings below differ.
%     2. Run settings for real time: stop time inf; no logging or saving to the
%        workspace (RT-LAB warns that these use memory on the target).
%     3. PreLoadFcn: opens THIS project by its absolute path, because RT-LAB opens
%        the copy from its own workspace, where the repo model's relative callback
%        cannot find the project.
%     4. InitFcn: sets LOAD_includeExt = false before load_params runs, so the ~1
%        million-sample extended cycle is not compiled in (profile 4 = CYCLE A on
%        the target; see load_params.m).
%     5. Pi link: PI_link (bmsPlatform.sldd) must be 0; the UDP blocks of the desktop
%        SITL link do not build for the target (a link to the Pi from the OP5033 will use
%        OPAL-RT's own UDP / CAN blocks). The BQ76952 emulator (SM_bms/AFE, 12. AFE C code)
%        is built in through the custom-code settings copied from cfgHarness; their paths
%        are absolute, so run defineParameters on each machine first.
%        (Older platform versions: SM_bms/BMS set to its STUB choice if present.)
%
%   The repo model is the only model that is edited. To update the RT-LAB copy,
%   re-import bmsTestPlatform.slx in RT-LAB and run this function again.

    arguments
        rtModelFile (1,1) string {mustBeFile}
    end
    prj = matlab.project.rootProject;
    assert(~isempty(prj), "Open the modularBMS project first.");
    repoModel = fullfile(prj.RootFolder, "02. Platform", "bmsTestPlatform.slx");
    assert(~strcmpi(char(rtModelFile), char(repoModel)), ...
        "This is the repo model. Give the path of the RT-LAB copy.");

    [~, mdl] = fileparts(rtModelFile);
    if bdIsLoaded(mdl)          % the repo model has the same name; only one can be loaded
        assert(get_param(mdl, "Dirty") == "off", ...
            "%s is open with unsaved changes. Save or close it first.", mdl);
        close_system(mdl, 0);
    end
    load_system(rtModelFile);
    c = onCleanup(@() close_system(mdl, 0));

    % 1. Local configuration instead of the dictionary reference
    cs = getActiveConfigSet(mdl);
    if isa(cs, "Simulink.ConfigSetRef")
        local = copy(getRefConfigSet(cs));
        local.Name = "cfgRT";
        attachConfigSet(mdl, local, true);
        setActiveConfigSet(mdl, "cfgRT");
        detachConfigSet(mdl, cs.Name);
    end

    % 2. Real-time run settings
    set_param(mdl, "StopTime", "inf", "SignalLogging", "off", "SaveTime", "off", ...
        "SaveOutput", "off", "SaveState", "off", "SaveFinalState", "off", ...
        "ReturnWorkspaceOutputs", "off");

    % 3. Open this project by absolute path
    set_param(mdl, "PreLoadFcn", sprintf( ...
        ['if isempty(matlab.project.rootProject)\n' ...
         '    %% Set by prepareRTModel.m: open the modularBMS project, then return here\n' ...
         '    d = pwd; openProject("%s"); cd(d);\n' ...
         'end'], prj.RootFolder));

    % 4. No extended load cycle in RT builds
    initFcn = string(get_param(mdl, "InitFcn"));
    if ~contains(initFcn, "LOAD_includeExt")
        set_param(mdl, "InitFcn", "LOAD_includeExt = false;   % set by prepareRTModel.m" ...
            + newline + initFcn);
    end

    % 5. Desktop-only Pi link must be off; BMS stub for older platform versions
    piLink = getValue(getEntry(getSection(Simulink.data.dictionary.open("bmsPlatform.sldd"), "Design Data"), "PI_link"));
    assert(piLink.Value == 0, "Set PI_link = 0 in bmsPlatform.sldd: the UDP SITL link does not build for the target.");
    bmsBlk = mdl + "/SM_bms/BMS";
    if getSimulinkBlockHandle(bmsBlk) > 0
        assert(get_param(bmsBlk, "Variant") == "on" && get_param(bmsBlk, "VariantControlMode") == "label", ...
            "SM_bms/BMS must be a Variant Subsystem in label mode (choices SIL, STUB).");
        set_param(bmsBlk, "LabelModeActiveChoice", "STUB");
    end

    save_system(mdl);
    fprintf("Prepared %s\n  configuration: cfgRT (%s, %s, step %s s)\n  project: %s\n", ...
        rtModelFile, get_param(mdl, "SolverType"), get_param(mdl, "SolverName"), ...
        get_param(mdl, "FixedStep"), prj.RootFolder);
    if getSimulinkBlockHandle(bmsBlk) > 0
        fprintf("  BMS variant: %s\n", get_param(bmsBlk, "LabelModeActiveChoice"));
    end
end
