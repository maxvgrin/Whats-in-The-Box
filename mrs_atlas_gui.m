function mrs_atlas_gui(savedResults)
% A point-and-click wrapper around run_mrs_atlas_composition. Load a cohort of
% patients (an Osprey MRSCont.mat or an Osprey job file), point it at an atlas,
% press START, and watch the log + results appear. Nothing here computes12
% anything new: every field maps to a cfg.* option of the orchestrator.
%
% Requirements (same as the toolbox): MATLAB, SPM12 and Osprey on the path,
% and an atlas (label NIfTI + FSL XML or CSV lookup). Set the SPM12 / Osprey
% paths in the GUI if they are not already on your MATLAB path.
% -------------------------------------------------------------------------


    % put the toolbox (this file's folder) on the path so the GUI can call it
    here = fileparts(mfilename('fullpath'));
    if ~isempty(here), addpath(here); end

    S = struct();                 % shared handle store

    % ---- colour theme --------------------------------------------------
    C = struct( ...
        'bg',      [0.945 0.957 0.972], ...   % window background
        'panel',   [1.000 1.000 1.000], ...   % cards
        'accent',  [0.094 0.357 0.553], ...   % deep blue (header, headings)
        'accentL', [0.886 0.925 0.965], ...   % light tint (step bars)
        'green',   [0.137 0.553 0.318], ...   % Start button
        'text',    [0.150 0.165 0.200], ...   % body text
        'muted',   [0.804 0.871 0.949], ...   % header subtitle
        'rowAlt',  [0.951 0.965 0.980]);       % table stripe
    S.theme = C;

    % ---- window --------------------------------------------------------
    S.fig = uifigure('Name','MRS Voxel Atlas Composition', ...
        'Position',[80 60 1400 900], 'Color',C.bg);
    G = uigridlayout(S.fig,[3 1]);
    G.RowHeight   = {'fit','1x','fit'};
    G.ColumnWidth = {'1x'};
    G.Padding     = [14 14 14 14];
    G.RowSpacing  = 12;
    G.BackgroundColor = C.bg;

    % ---- header banner -------------------------------------------------
    banner = uipanel(G,'BackgroundColor',C.accent,'BorderType','none');
    banner.Layout.Row = 1;
    hdr = uigridlayout(banner,[2 1]);
    hdr.RowHeight = {'fit','fit'}; hdr.RowSpacing = 3;
    hdr.Padding = [18 14 18 14]; hdr.BackgroundColor = C.accent;
    titleLbl = uilabel(hdr,'Text','What''s in the Box (and Where Is It?)', ...
        'FontSize',24,'FontWeight','bold','FontColor',[1 1 1]);
    titleLbl.Layout.Row = 1;
    sub = uilabel(hdr, ...
        'Text','MRS voxel anatomy and location in MNI space', ...
        'FontSize',14,'FontColor',C.muted);
    sub.Layout.Row = 2;

    % ---- middle: two columns (controls | results) ---------------------
    mid = uigridlayout(G,[1 2]);
    mid.Layout.Row = 2; mid.ColumnWidth = {430,'1x'};
    mid.Padding = [0 0 0 0]; mid.ColumnSpacing = 14;
    mid.BackgroundColor = C.bg;

    % ====================== left: one simple controls card =============
    form = uipanel(mid,'BorderType','line','BackgroundColor',C.panel,'Scrollable','on');
    form.Layout.Column = 1;
    advRow = 10;
    fg = uigridlayout(form,[10 1]);
    fg.RowHeight   = {'fit','fit','fit','fit',48,'fit','fit','fit','fit',0};
    fg.ColumnWidth = {'1x'};
    fg.Padding = [16 16 16 16]; fg.RowSpacing = 11;
    fg.BackgroundColor = C.panel;

    % --- Step 1: select a BIDS dataset folder (the whole cohort) -------
    secHeader(fg,1,'1.   Select your BIDS dataset   (whole cohort)');
    r2 = uigridlayout(fg,[3 2]); r2.Layout.Row = 2;
    r2.RowHeight = {'fit','fit','fit'}; r2.ColumnWidth = {'1x','fit'};
    r2.Padding = [0 0 0 0]; r2.RowSpacing = 4; r2.ColumnSpacing = 8;
    r2.BackgroundColor = C.panel;
    S.bidsDir = uieditfield(r2,'text','Placeholder','Choose your BIDS study folder…', ...
        'ValueChangedFcn',@(~,~)refreshBIDS());
    S.bidsDir.Layout.Row = 1; S.bidsDir.Layout.Column = 1;
    bB = uibutton(r2,'Text','Browse…','FontWeight','bold', ...
        'BackgroundColor',C.accentL,'FontColor',C.accent, ...
        'ButtonPushedFcn',@(~,~)pickBIDS());
    bB.Layout.Row = 1; bB.Layout.Column = 2;
    S.bidsInfo = uilabel(r2,'Text','Every participant (sub-*) in the folder is processed together.', ...
        'FontColor',[0.45 0.45 0.50]);
    S.bidsInfo.Layout.Row = 2; S.bidsInfo.Layout.Column = [1 2];

    bReview=uibutton(r2,'Text','Select / name ROIs and review files', ...
        'ButtonPushedFcn',@(~,~)reviewAssignments());
    bReview.Layout.Row=3; bReview.Layout.Column=[1 2];
    S.assignments=table(); S.batch=[];

    % --- Step 2: brain atlas (preset dropdown) -------------------------
    secHeader(fg,3,'2.   Choose a brain atlas');
    S.presets   = mva_discover_atlases();
    customLabel = 'Custom (set in Advanced settings)';
    atlasRow=uigridlayout(fg,[2 2]); atlasRow.Layout.Row=4;
    atlasRow.RowHeight={'fit','fit'}; atlasRow.ColumnWidth={'1x','fit'}; atlasRow.Padding=[0 0 0 0];
    initialSource='Custom'; if ~isempty(S.presets), initialSource=S.presets(1).source; end
    S.atlasSource=uidropdown(atlasRow,'Items',{'CAT12','FSL','Custom'},'Value',initialSource,'ValueChangedFcn',@(~,~)refreshAtlases());
    uibutton(atlasRow,'Text','Refresh','ButtonPushedFcn',@(~,~)refreshAtlases());
    S.atlasPreset = uidropdown(atlasRow, ...
        'Items',{customLabel}, 'Value',customLabel, ...
        'FontSize',13,'ValueChangedFcn',@(~,~)applyPreset());
    S.atlasPreset.Layout.Row = 2; S.atlasPreset.Layout.Column=[1 2];

    % --- the one big action -------------------------------------------
    S.startBtn = uibutton(fg,'Text','▶   Start','FontSize',18,'FontWeight','bold', ...
        'BackgroundColor',C.green,'FontColor',[1 1 1],'ButtonPushedFcn',@(~,~)runIt());
    S.startBtn.Layout.Row = 5;

    r6 = uigridlayout(fg,[1 2]); r6.Layout.Row = 6;
    r6.ColumnWidth = {'1x','fit'}; r6.Padding = [0 0 0 0];
    r6.ColumnSpacing = 10; r6.BackgroundColor = C.panel;
    S.demo = uicheckbox(r6,'Text','Demo mode (no data needed)','Value',false,'FontColor',C.text, ...
        'Tooltip','Run a built-in synthetic cohort to test the app without SPM/Osprey/data.');
    S.demo.Layout.Column = 1;
    S.openBtn = uibutton(r6,'Text','📂  Open output','FontColor',C.accent,'Enable','off', ...
        'ButtonPushedFcn',@(~,~)openOut());
    S.openBtn.Layout.Column = 2;

    S.status = uilabel(fg,'Text','Ready.','FontWeight','bold','FontColor',C.accent);
    S.status.Layout.Row = 7;

    r8 = uigridlayout(fg,[1 2]); r8.Layout.Row = 8;
    r8.ColumnWidth = {'fit','1x'}; r8.Padding = [0 0 0 0];
    r8.ColumnSpacing = 18; r8.BackgroundColor = C.panel;
    S.elapsed = uilabel(r8,'Text','Elapsed  00:00','FontColor',[0.40 0.40 0.45]);
    S.elapsed.Layout.Column = 1;
    S.remain  = uilabel(r8,'Text','Remaining  --:--','FontWeight','bold','FontColor',[0.40 0.40 0.45]);
    S.remain.Layout.Column = 2;

    % --- Advanced settings (collapsible) -------------------------------
    S.advBtn = uibutton(fg,'Text','⚙   Advanced settings   ▸', ...
        'HorizontalAlignment','left','FontColor',C.accent,'BackgroundColor',C.panel, ...
        'ButtonPushedFcn',@(~,~)toggleAdv());
    S.advBtn.Layout.Row = 9;

    S.advPanel = uipanel(fg,'BorderType','line','BackgroundColor',C.panel,'Visible','off');
    S.advPanel.Layout.Row = advRow;
    ag = uigridlayout(S.advPanel,[18 3]);
    ag.RowHeight = repmat({'fit'},1,18); ag.ColumnWidth = {150,'1x',82};
    ag.Padding = [10 10 10 10]; ag.RowSpacing = 7; ag.BackgroundColor = C.panel;

    % custom atlas (used only when the preset is set to "Custom")
    lbl(ag,1,'Custom atlas (used when preset = Custom)','bold');
    gridLabel(ag,'Atlas image (labels)',2);
    S.atlasImage = uieditfield(ag,'text','Placeholder','*.nii / *.nii.gz');
    S.atlasImage.Layout = lay(2,2);
    bb = uibutton(ag,'Text','Upload…','ButtonPushedFcn',@(~,~)pickFile(S.atlasImage, ...
        {'*.nii;*.nii.gz','NIfTI (*.nii, *.nii.gz)'})); bb.Layout = lay(2,3);
    gridLabel(ag,'Region names from',3);
    S.lutType = uidropdown(ag,'Items',{'FSL XML','CSV LUT (value,name)'},'Value','FSL XML');
    S.lutType.Layout = lay(3,2);
    gridLabel(ag,'Region-name file',4);
    S.atlasLUT = uieditfield(ag,'text','Placeholder','*.xml or *.csv');
    S.atlasLUT.Layout = lay(4,2);
    bb = uibutton(ag,'Text','Upload…','ButtonPushedFcn',@(~,~)pickLookup()); bb.Layout = lay(4,3);
    gridLabel(ag,'Label type',5);
    S.atlasMode = uidropdown(ag,'Items',{'maxprob','prob'},'Value','maxprob');
    S.atlasMode.Layout = lay(5,2);

    % already-processed Osprey output (overrides the raw upload above)
    lbl(ag,6,'Already have Osprey output? (overrides the upload)','bold');
    gridLabel(ag,'Type',7);
    S.srcType = uidropdown(ag,'Items',{'(none)','Osprey MRSCont .mat','Osprey job file'}, ...
        'Value','(none)'); S.srcType.Layout = lay(7,2);
    gridLabel(ag,'File',8);
    S.srcFile = uieditfield(ag,'text','Placeholder','MRSCont.mat or job file (optional)');
    S.srcFile.Layout = lay(8,2);
    bb = uibutton(ag,'Text','Browse','ButtonPushedFcn',@(~,~)pickSource()); bb.Layout = lay(8,3);

    % toolbox folders
    lbl(ag,9,'Toolbox folders (leave blank if already on your MATLAB path)','bold');
    gridLabel(ag,'SPM12 folder',10);
    S.spmPath = uieditfield(ag,'text'); S.spmPath.Layout = lay(10,2);
    bb = uibutton(ag,'Text','Browse','ButtonPushedFcn',@(~,~)pickDir(S.spmPath)); bb.Layout = lay(10,3);
    gridLabel(ag,'Osprey folder',11);
    S.ospreyPath = uieditfield(ag,'text'); S.ospreyPath.Layout = lay(11,2);
    bb = uibutton(ag,'Text','Browse','ButtonPushedFcn',@(~,~)pickDir(S.ospreyPath)); bb.Layout = lay(11,3);

    % output
    lbl(ag,12,'Output','bold');
    gridLabel(ag,'Save results to',13);
    S.outDir = uieditfield(ag,'text','Value',fullfile(pwd,'mrs_atlas_out'));
    S.outDir.Layout = lay(13,2);
    bb = uibutton(ag,'Text','Browse','ButtonPushedFcn',@(~,~)pickDir(S.outDir)); bb.Layout = lay(13,3);
    gridLabel(ag,'Group pie slices below %',14);
    S.otherThresh = uieditfield(ag,'numeric','Value',2,'Limits',[0 100]);
    S.otherThresh.Layout = lay(14,2);

    gridLabel(ag,'Osprey sequence',15);
    S.seqType=uidropdown(ag,'Items',{'unedited','MEGA','HERMES','HERCULES'},'Value','unedited'); S.seqType.Layout=lay(15,2);
    gridLabel(ag,'Editing targets',16);
    S.editTarget=uieditfield(ag,'text','Value','none','Placeholder','e.g. GABA,GSH'); S.editTarget.Layout=lay(16,2);

    S.enableParallel=uicheckbox(ag,'Text','Enable parallel processing','Value',false);
    S.enableParallel.Layout=lay(17,2);
    gridLabel(ag,'Workers',18);
    S.workers=uieditfield(ag,'numeric','Value',4,'Limits',[1 Inf],'RoundFractionalValues','on');
    S.workers.Layout=lay(18,2);

    % ====================== right: results (tabbed) ====================
    res = uipanel(mid,'Title','Results','FontWeight','bold', ...
        'FontSize',14,'BackgroundColor',C.panel,'ForegroundColor',C.accent);
    res.Layout.Column = 2;
    resG = uigridlayout(res,[1 1]);
    resG.Padding = [6 6 6 6]; resG.BackgroundColor = C.panel;
    S.tabs = uitabgroup(resG);

    % ---- Tab 1: composition (pie + table) -----------------------------
    tabComp = uitab(S.tabs,'Title','Composition','BackgroundColor',C.panel);
    rg = uigridlayout(tabComp,[4 1]);
    rg.RowHeight = {'1x','fit','1.1x','fit'}; rg.Padding = [10 10 10 10]; rg.RowSpacing = 8;
    rg.BackgroundColor = C.panel;

    S.pieAx = uiaxes(rg); S.pieAx.Layout.Row = 1;
    title(S.pieAx,'Composition pie chart'); axis(S.pieAx,'off');
    S.pieAx.BackgroundColor = C.panel;

    tblHdr = uilabel(rg, ...
        'Text','  Percentage of voxel per region  (density-weighted; plus per-subject mean & SD)', ...
        'FontWeight','bold','FontSize',13,'FontColor',C.accent,'BackgroundColor',C.accentL);
    tblHdr.Layout.Row = 2;

    S.tbl = uitable(rg);
    S.tbl.Layout.Row = 3;
    S.tbl.ColumnName = {'Region','Density %','Mean %','SD %'};
    S.tbl.RowName    = {};
    S.tbl.ColumnWidth = {'auto', 90, 80, 55};
    S.tbl.FontSize   = 12;
    S.tbl.BackgroundColor = [C.panel; C.rowAlt];   % zebra striping

    chartTools=uigridlayout(rg,[1 2]); chartTools.Layout.Row=4;
    chartTools.RowHeight={'fit'};
    uibutton(chartTools,'Text','Save pie chart','ButtonPushedFcn',@(~,~)saveChart('pie'));
    uibutton(chartTools,'Text','Save bar chart','ButtonPushedFcn',@(~,~)saveChart('bar'));
    tabBar=uitab(S.tabs,'Title','Bar chart','BackgroundColor',C.panel);
    barGrid=uigridlayout(tabBar,[2 1]); barGrid.RowHeight={'1x','fit'};
    S.barAx=uiaxes(barGrid);
    uibutton(barGrid,'Text','Save bar chart','ButtonPushedFcn',@(~,~)saveChart('bar'));
    S.chartComp=[];

    % ---- Tab 2: voxel-density map in MNI space ------------------------
    % Orthogonal slices (sagittal/coronal/axial) of the across-subject
    % voxel-density map, overlaid (hot) on an MNI anatomical underlay.
    tabDens = uitab(S.tabs,'Title','Voxel density (MNI)','BackgroundColor',C.panel);
    dg = uigridlayout(tabDens,[7 1]);
    dg.RowHeight = {'1x','fit','fit','fit','fit',120,'fit'}; dg.Padding = [10 10 10 10]; dg.RowSpacing = 8;
    dg.BackgroundColor = C.panel;

    axRow = uigridlayout(dg,[1 4]); axRow.Layout.Row = 1;
    axRow.ColumnWidth = {'1x','1x','1x',74};
    axRow.ColumnSpacing = 6; axRow.Padding = [0 0 0 0]; axRow.BackgroundColor = C.panel;
    S.sagAx = uiaxes(axRow); S.sagAx.Layout.Column = 1;
    S.corAx = uiaxes(axRow); S.corAx.Layout.Column = 2;
    S.axAx  = uiaxes(axRow); S.axAx.Layout.Column  = 3;
    for a = [S.sagAx S.corAx S.axAx]
        a.BackgroundColor = [0 0 0]; a.XTick = []; a.YTick = [];
    end
    title(S.sagAx,'Sagittal'); title(S.corAx,'Coronal'); title(S.axAx,'Axial');
    S.cbarAx = uiaxes(axRow); S.cbarAx.Layout.Column = 4;   % "Number of subjects"
    S.cbarAx.XTick = []; S.cbarAx.YTick = [];

    % three slice-position sliders (filled in once a density map is loaded)
    slRow = uigridlayout(dg,[2 3]); slRow.Layout.Row = 2;
    slRow.RowHeight = {'fit','fit'}; slRow.RowSpacing = 2;
    slRow.Padding = [0 0 0 0]; slRow.ColumnSpacing = 12; slRow.BackgroundColor = C.panel;
    sLbl = uilabel(slRow,'Text','Sagittal (X)','FontColor',C.text); sLbl.Layout = lay(1,1);
    cLbl = uilabel(slRow,'Text','Coronal (Y)','FontColor',C.text);  cLbl.Layout = lay(1,2);
    aLbl = uilabel(slRow,'Text','Axial (Z)','FontColor',C.text);    aLbl.Layout = lay(1,3);
    S.sagSld = uislider(slRow,'Limits',[1 2],'Value',1,'MajorTicks',[], ...
        'ValueChangedFcn',@(~,~)renderDensity()); S.sagSld.Layout = lay(2,1);
    S.corSld = uislider(slRow,'Limits',[1 2],'Value',1,'MajorTicks',[], ...
        'ValueChangedFcn',@(~,~)renderDensity()); S.corSld.Layout = lay(2,2);
    S.axSld  = uislider(slRow,'Limits',[1 2],'Value',1,'MajorTicks',[], ...
        'ValueChangedFcn',@(~,~)renderDensity()); S.axSld.Layout = lay(2,3);

    % ---- containment analysis: centre of gravity + sphere/box coverage ---
    % Relative to the density's centre of gravity (MNI), how large a sphere (or
    % box) is needed to capture X% of the voxel density. Clustered voxels -> a
    % small radius; spread-out voxels -> a large one. The outline is drawn on
    % the slices above and the atlas regions it overlaps are listed below.
    ctrlRow = uigridlayout(dg,[1 6]); ctrlRow.Layout.Row = 3;
    ctrlRow.ColumnWidth = {'fit','fit','fit','fit','fit','1x'};
    ctrlRow.ColumnSpacing = 8; ctrlRow.Padding = [0 0 0 0]; ctrlRow.BackgroundColor = C.panel;
    shpLbl = uilabel(ctrlRow,'Text','Containment shape','FontColor',C.text,'FontWeight','bold');
    shpLbl.Layout.Column = 1;
    S.contShape = uidropdown(ctrlRow,'Items',{'Sphere','Box'},'Value','Sphere', ...
        'ValueChangedFcn',@(~,~)updateContainment());
    S.contShape.Layout.Column = 2;
    covLbl = uilabel(ctrlRow,'Text','capturing','FontColor',C.text); covLbl.Layout.Column = 3;
    S.contCover = uidropdown(ctrlRow,'Items',{'80%','90%','95%'},'Value','90%', ...
        'ValueChangedFcn',@(~,~)updateContainment());
    S.contCover.Layout.Column = 4;
    ofLbl = uilabel(ctrlRow,'Text','of the voxel density','FontColor',C.text); ofLbl.Layout.Column = 5;
    S.contSummary = uilabel(ctrlRow,'Text','','FontColor',C.accent,'FontWeight','bold','FontSize',13);
    S.contSummary.Layout.Column = 6;

    % ---- highlight one atlas region: draw its exact outline on the slices --
    hiRow = uigridlayout(dg,[1 3]); hiRow.Layout.Row = 4;
    hiRow.ColumnWidth = {'fit',260,'1x'};
    hiRow.ColumnSpacing = 8; hiRow.Padding = [0 0 0 0]; hiRow.BackgroundColor = C.panel;
    hiLbl = uilabel(hiRow,'Text','Highlight region','FontColor',C.text,'FontWeight','bold');
    hiLbl.Layout.Column = 1;
    S.contHi = uidropdown(hiRow,'Items',{'(none)'},'ItemsData',0,'Value',0, ...
        'ValueChangedFcn',@(~,~)highlightChanged());
    S.contHi.Layout.Column = 2;
    S.contHiKey = uilabel(hiRow, ...
        'Text','orange = full atlas region   •   bright yellow = part inside the shape', ...
        'FontColor',[0.45 0.45 0.50],'FontSize',12);
    S.contHiKey.Layout.Column = 3;

    S.densInfo = uilabel(dg, ...
        'Text','Run the toolbox (or Demo mode) to see where the MRS voxels land in MNI space.', ...
        'FontColor',[0.45 0.45 0.50],'FontSize',12);
    S.densInfo.Layout.Row = 5;

    S.contList = uitextarea(dg,'Editable','off','Value',{''}, ...
        'FontName','monospaced','FontColor',C.text,'BackgroundColor',[0.985 0.988 0.992]);
    S.contList.Layout.Row = 6;

    viewTools=uigridlayout(dg,[1 5]); viewTools.Layout.Row=7;
    viewTools.ColumnWidth={'fit','1x','1x','fit','fit'}; viewTools.Padding=[0 0 0 0];
    uilabel(viewTools,'Text','ROI:');
    S.roiSelect=uidropdown(viewTools,'Items',{'ROI'},'ValueChangedFcn',@(~,~)switchROI());
    S.scale=uidropdown(viewTools,'Items',{'Participants','Percent'},'ValueChangedFcn',@(~,~)renderDensity());
    uibutton(viewTools,'Text','Export current heatmap','ButtonPushedFcn',@(~,~)exportHeatmap());
    uibutton(viewTools,'Text','Open results','ButtonPushedFcn',@(~,~)openResults());

    S.densReady = false;
    S.cont      = [];      % last-computed containment (COG, radius, regions)
    S.densAtlas = [];      % atlas label volume on the density grid (for overlap)
    S.densInside = [];     % 3D logical: voxels inside the current sphere/box
    S.hiMask    = [];      % 3D logical: highlighted atlas region
    S.hiInbox   = [];      % 3D logical: highlighted region ∩ containment shape

    % ---- bottom: activity log -----------------------------------------
    logPanel = uipanel(G,'Title','Activity log','FontWeight','bold','FontSize',13, ...
        'BackgroundColor',C.panel,'ForegroundColor',C.accent);
    logPanel.Layout.Row = 3;
    lgrid = uigridlayout(logPanel,[1 1]);
    lgrid.RowHeight = {110}; lgrid.Padding = [8 8 8 8]; lgrid.BackgroundColor = C.panel;
    S.log = uitextarea(lgrid,'Editable','off', ...
        'Value',{'Log output will appear here.'}, ...
        'FontName','monospaced','FontColor',C.text, ...
        'BackgroundColor',[0.985 0.988 0.992]);

    % ---- elapsed-time stopwatch + clean shutdown -----------------------
    S.t0  = [];                       % tic handle while a run is active
    S.tmr = timer('ExecutionMode','fixedRate','Period',1,'BusyMode','drop', ...
        'TimerFcn',@(~,~)tickElapsed());
    S.fig.CloseRequestFcn = @(~,~)onClose();

    % auto-fill the atlas fields from the default preset (quietly)
    refreshAtlases();
    if nargin>0 && ~isempty(savedResults)
        loaded=load(savedResults);
        if isfield(loaded,'batch'), installResults(loaded.batch);
        elseif isfield(loaded,'results'), installResults(loaded.results); end
    end

    % ===================================================================
    %  nested helpers
    % ===================================================================
    function L = lay(r,c), L = matlab.ui.layout.GridLayoutOptions; L.Row=r; L.Column=c; end

    % section header (tinted accent bar) spanning a 3-column grid (advanced)
    function lbl(parent,r,txt,~)
        h = uilabel(parent,'Text',['  ' txt],'FontWeight','bold','FontSize',13, ...
            'FontColor',C.accent,'BackgroundColor',C.accentL);
        h.Layout = lay(r,[1 3]);
    end

    % section header for the single-column main form
    function secHeader(parent,r,txt)
        h = uilabel(parent,'Text',['  ' txt],'FontWeight','bold','FontSize',14, ...
            'FontColor',C.accent,'BackgroundColor',C.accentL);
        h.Layout.Row = r; h.Layout.Column = 1;
    end

    % plain field label at column 1 of a 3-column grid (advanced panel)
    function gridLabel(g,txt,r)
        h = uilabel(g,'Text',txt,'FontColor',C.text,'FontSize',12);
        h.Layout.Row = r; h.Layout.Column = 1;
    end

    % show/hide the Advanced settings panel (collapses its grid row)
    function toggleAdv()
        show = strcmp(S.advPanel.Visible,'off');
        S.advPanel.Visible = onoff(show);
        if show
            fg.RowHeight{advRow} = 'fit';
            S.advBtn.Text = '⚙   Advanced settings   ▾';
        else
            fg.RowHeight{advRow} = 0;
            S.advBtn.Text = '⚙   Advanced settings   ▸';
        end
    end

    function pickFile(field, filter)
        [f,p] = uigetfile(filter,'Select file');
        figure(S.fig);                      % keep app in front of the dialog
        if isequal(f,0), return; end
        field.Value = fullfile(p,f);
    end

    function pickDir(field)
        d = uigetdir(pwd,'Select folder');
        figure(S.fig);
        if isequal(d,0), return; end
        field.Value = d;
        if isequal(field,S.spmPath), refreshAtlases(); end
    end

    function pickBIDS()
        d = uigetdir(pwd,'Select your BIDS dataset folder (the whole study)');
        figure(S.fig);
        if isequal(d,0), return; end
        S.bidsDir.Value = d;
        refreshBIDS();
        if ~isempty(S.assignments), reviewAssignments(); end
    end

    % count sub-* participants in the chosen BIDS folder and report it,
    % so it's clear the run covers a cohort (not a single participant).
    function refreshBIDS()
        try
            S.assignments=mva_scan_bids(strtrim(S.bidsDir.Value));
            S.bidsInfo.Text=sprintf('%d MRS acquisitions; ROIs: %s',height(S.assignments),strjoin(unique(S.assignments.ROI),', '));
        catch ME
            S.assignments=table(); S.bidsInfo.Text=ME.message;
        end
    end

    function reviewAssignments()
        if isempty(S.assignments), refreshBIDS(); end
        if isempty(S.assignments), uialert(S.fig,'No MRS acquisitions found.','Dataset'); return; end
        S.assignments=mva_review_assignments(S.assignments);
        S.bidsInfo.Text=sprintf('%d acquisitions selected: %s',sum(S.assignments.Include),strjoin(unique(S.assignments.ROI(S.assignments.Include)),', '));
    end

    function pickSource()
        if contains(S.srcType.Value,'MRSCont')
            filt = {'*.mat','MAT-file (*.mat)'};
        elseif contains(S.srcType.Value,'job')
            filt = {'*.m;*.csv','Osprey job (*.m, *.csv)'};
        else
            filt = {'*.mat;*.m;*.csv','Osprey output (*.mat, *.m, *.csv)'};
        end
        pickFile(S.srcFile, filt);
    end

    function pickLookup()
        if strcmp(S.lutType.Value,'FSL XML')
            filt = {'*.xml','FSL atlas XML (*.xml)'};
        else
            filt = {'*.csv','CSV lookup (*.csv)'};
        end
        pickFile(S.atlasLUT, filt);
    end

    % preset dropdown -> auto-fill the (advanced) atlas image/lookup/mode
    % fields. "Custom" leaves them untouched so you can Browse to your own.
    % Pass silent=true for the startup call so no dialogs pop up.
    function refreshAtlases()
        sp=''; if isfield(S,'spmPath'), sp=strtrim(S.spmPath.Value); end
        S.presets=mva_discover_atlases(sp);
        ix=strcmp({S.presets.source},S.atlasSource.Value);
        items=[{S.presets(ix).name},{customLabel}];
        S.atlasPreset.Items=items; S.atlasPreset.Value=items{1};
        applyPreset(true);
    end

    function applyPreset(silent)
        if nargin<1, silent=false; end %#ok<NASGU>
        v=S.atlasPreset.Value;
        if strcmp(v,customLabel), return; end
        P=S.presets(find(strcmp({S.presets.name},v),1));
        S.atlasImage.Value=P.img; S.atlasLUT.Value=P.lut;
        if strcmp(P.lutType,'xml'), S.lutType.Value='FSL XML';
        else, S.lutType.Value='CSV LUT (value,name)'; end
        S.atlasMode.Value=P.mode;
    end

    function openOut()
        od = S.outDir.Value;
        if exist(od,'dir'), local_reveal(od); end
    end

    function setStatus(txt, color)
        S.status.Text = txt; S.status.FontColor = color; drawnow;
    end

    % stopwatch tick (timer-driven, ~1 Hz)
    function tickElapsed()
        if ~isempty(S.t0) && isvalid(S.elapsed)
            S.elapsed.Text = sprintf('Elapsed  %s', local_mmss(toc(S.t0)));
        end
    end

    % per-subject progress callback handed to the toolbox -> live ETA
    function gui_progress(done, total)
        if isempty(S.t0), return; end
        el = toc(S.t0);
        if done <= 0
            setStatus(sprintf('Warping %d subject(s) to MNI…', total), [0.85 0.5 0]);
            S.remain.Text = 'Remaining  estimating…';
        else
            remain = max(0, (el/done) * (total - done));
            setStatus(sprintf('Warping subject %d of %d to MNI…', done, total), [0.85 0.5 0]);
            S.remain.Text = sprintf('Remaining  ~%s', local_mmss(remain));
        end
        S.remain.FontColor = [0.85 0.45 0.0];     % highlight while running
        S.elapsed.Text = sprintf('Elapsed  %s', local_mmss(el));
        drawnow limitrate;
    end

    % stop the timer and close cleanly (avoids orphaned timer objects)
    function onClose()
        try
            stop(S.tmr); delete(S.tmr);
        catch
        end
        delete(S.fig);
    end

    function appendLog(lines)
        if ischar(lines), lines = {lines}; end
        S.log.Value = [S.log.Value; lines(:)];
        scroll(S.log,'bottom'); drawnow;
    end

    % ---- build cfg from the form, with validation ----------------------
    function cfg = buildCfg()
        cfg = struct();

        % --- input: a BIDS dataset (default) or, in Advanced, existing
        %     Osprey output which overrides the BIDS folder if provided.
        src = strtrim(S.srcFile.Value);
        useExisting = ~isempty(src) && ~strcmp(S.srcType.Value,'(none)');
        if useExisting
            assert(exist(src,'file')==2, 'Osprey output file not found:\n%s', src);
            % Route by the file's actual extension, not the dropdown label, so a
            % .mat container is never handed to the Osprey job loader (which only
            % accepts .m/.csv/.json) and a job file is never loaded as a MRSCont.
            [~,~,ext] = fileparts(src);
            switch lower(ext)
                case '.mat'
                    cfg.mrscontMat = src;
                case {'.m','.csv','.json'}
                    cfg.jobFile = src;
                otherwise
                    error(['Unsupported source file:\n%s\n\nPick an Osprey ' ...
                        'MRSCont container (.mat) or an Osprey job file ' ...
                        '(.m, .csv or .json).'], src);
            end
        else
            bids = strtrim(S.bidsDir.Value);
            assert(~isempty(bids), ...
                'Select your BIDS dataset folder (or set existing Osprey output in Advanced).');
            assert(exist(bids,'dir')==7, 'BIDS folder not found:\n%s', bids);
            cfg.bidsDir = bids;
            if isempty(S.assignments), refreshBIDS(); end
            S.assignments=mva_validate_assignments(S.assignments);
            if any(~strcmp(S.assignments.Status(S.assignments.Include),'OK')) || ~any(S.assignments.Include)
                reviewAssignments();
            end
            cfg.assignments=mva_validate_assignments(S.assignments);
            assert(any(cfg.assignments.Include) && all(strcmp(cfg.assignments.Status(cfg.assignments.Include),'OK')), ...
                'Resolve selected assignments in the file review table.');
        end

        atlasMsg = ['Atlas not found. Pick a preset from the dropdown, or set a ' ...
                    'Custom atlas under Advanced settings.'];
        ai = strtrim(S.atlasImage.Value);
        assert(~isempty(ai) && exist(ai,'file')==2, '%s\n%s', atlasMsg, ai);
        cfg.atlasImage = ai;

        lut = strtrim(S.atlasLUT.Value);
        assert(~isempty(lut) && exist(lut,'file')==2, ...
            'Atlas region-name file not found:\n%s', lut);
        cfg.atlasSource=S.atlasSource.Value;
        if strcmp(S.atlasPreset.Value,customLabel), cfg.atlasSource='Custom'; end
        if strcmp(cfg.atlasSource,'CAT12')
            cfg.atlasLUT=lut;
        elseif strcmp(S.lutType.Value,'FSL XML')
            cfg.atlasXML = lut;
        else
            cfg.atlasLUT = lut;
        end

        cfg.atlasMode = S.atlasMode.Value;

        if ~isempty(strtrim(S.spmPath.Value)),    cfg.spmPath    = strtrim(S.spmPath.Value);    end
        if ~isempty(strtrim(S.ospreyPath.Value)), cfg.ospreyPath = strtrim(S.ospreyPath.Value); end

        od = strtrim(S.outDir.Value);
        if isempty(od), od = fullfile(pwd,'mrs_atlas_out'); end
        cfg.outDir = od;

        cfg.seqType=S.seqType.Value;
        cfg.editTarget=cellstr(strtrim(split(string(S.editTarget.Value),',')))';
        if strcmp(cfg.seqType,'unedited'), cfg.editTarget={'none'}; end
        cfg.otherThreshPct = S.otherThresh.Value;
        cfg.topN=12; cfg.saveCharts=false;
        cfg.enableParallel=S.enableParallel.Value; cfg.workers=S.workers.Value;
    end

    % ---- the Start handler ---------------------------------------------
    function runIt()
        demo = S.demo.Value;
        try
            if demo
                cfg = struct( ...
                    'outDir',         strtrim(S.outDir.Value), ...
                    'atlasMode',      'maxprob', ...
                    'otherThreshPct', S.otherThresh.Value, ...
                    'topN',           12);
                assert(~isempty(cfg.outDir), 'Choose an output folder.');
            else
                cfg = buildCfg();
            end
        catch ME
            uialert(S.fig, ME.message, 'Missing / invalid input');
            return;
        end

        S.startBtn.Enable = 'off'; S.openBtn.Enable = 'off'; S.demo.Enable = 'off';
        S.log.Value = {''};
        cla(S.pieAx,'reset'); axis(S.pieAx,'off');
        cla(S.barAx,'reset'); S.chartComp=[];
        S.tbl.Data = {};
        S.densReady = false;
        for axh = [S.sagAx S.corAx S.axAx], cla(axh,'reset'); axh.BackgroundColor=[0 0 0]; axh.XTick=[]; axh.YTick=[]; end
        title(S.sagAx,'Sagittal'); title(S.corAx,'Coronal'); title(S.axAx,'Axial');
        S.densInfo.Text = 'Computing… the voxel-density map will appear here when the run finishes.';
        appendLog(sprintf('=== Run started %s ===', char(datetime('now'))));

        % start the elapsed-time stopwatch + reset the remaining estimate
        S.t0 = tic;
        S.elapsed.Text = 'Elapsed  00:00';
        S.remain.Text  = 'Remaining  --:--';
        S.remain.FontColor = [0.40 0.40 0.45];
        start(S.tmr);

        % capture any fprintf output to a diary file so it shows in the log
        logFile = fullfile(tempdir, sprintf('mva_gui_log_%d.txt', feature('getpid')));
        if exist(logFile,'file'), delete(logFile); end

        results = [];
        diary(logFile); diary on;
        cleanup = onCleanup(@() diary('off'));
        try
            if demo
                setStatus('Running demo (synthetic cohort)…', [0.85 0.5 0]);
                results = local_run_demo(cfg, @appendLog);
            else
                setStatus('Loading data… (an ETA appears once warping starts)', [0.85 0.5 0]);
                cfg.progressFcn = @gui_progress;       % live per-subject ETA
                results = run_mrs_atlas_composition(cfg);
            end
            ok = true; err = [];
        catch ME
            ok = false; err = ME;
        end
        diary off; clear cleanup;

        stop(S.tmr);
        elapsedTot = toc(S.t0); S.t0 = [];
        S.elapsed.Text = sprintf('Total  %s', local_mmss(elapsedTot));
        S.remain.Text  = 'Remaining  done';
        S.remain.FontColor = [0.40 0.40 0.45];

        % surface whatever was printed
        if exist(logFile,'file')
            txt = local_readlines(logFile);
            if ~isempty(txt), appendLog(txt); end
            delete(logFile);
        end

        tstr = local_mmss(elapsedTot);
        if ok
            if demo
                setStatus(sprintf('Demo done in %s — charts below are from synthetic data.', tstr), [0.1 0.5 0.1]);
            else
                setStatus(sprintf('Done in %s. Outputs written to the output folder.', tstr), [0.1 0.5 0.1]);
            end
            appendLog(sprintf('=== Finished OK in %s ===', tstr));
            installResults(results);
            S.openBtn.Enable = onoff(exist(cfg.outDir,'dir')==7);
        else
            setStatus('Failed — see log and error dialog.', [0.7 0 0]);
            appendLog(['ERROR: ' err.message]);
            uialert(S.fig, err.message, 'Run failed');
        end
        S.startBtn.Enable = 'on'; S.demo.Enable = 'on';
    end

    function installResults(results)
        if isfield(results,'rois')
            S.batch=results;
        else
            roi='ROI'; if isfield(results,'roi'), roi=results.roi; end
            S.batch=struct('rois',{{roi}},'results',{{results}});
        end
        S.roiSelect.Items=S.batch.rois; S.roiSelect.Value=S.batch.rois{1};
        switchROI();
    end

    function switchROI()
        if isempty(S.batch), return; end
        k=find(strcmp(S.batch.rois,S.roiSelect.Value),1);
        S.cont=[]; S.hiMask=[]; S.hiInbox=[];
        showResults([],S.batch.results{k});
    end

    function openResults()
        [fn,fp]=uigetfile('*.mat','Open cohort_results.mat or results.mat');
        if isequal(fn,0), return; end
        try
            loaded=load(fullfile(fp,fn));
            if isfield(loaded,'batch'), installResults(loaded.batch);
            elseif isfield(loaded,'results'), installResults(loaded.results);
            else, error('Select a saved toolbox result.'); end
        catch ME, uialert(S.fig,ME.message,'Cannot load results'); end
    end

    function saveChart(kind)
        if isempty(S.chartComp), uialert(S.fig,'Load or run an ROI first.','Save chart'); return; end
        [fn,fp,filter]=uiputfile({'*.png','PNG';'*.pdf','PDF'},['Save ' kind ' chart'],[kind '_chart.png']);
        if isequal(fn,0), return; end
        [~,~,ext]=fileparts(fn);
        if isempty(ext)
            if filter==2, fn=[fn '.pdf']; else, fn=[fn '.png']; end
        end
        try
            f=figure('Visible','off','Color','w','Position',[100 100 1100 680]);
            cleaner=onCleanup(@()close(f));
            ax=axes(f);
            if strcmp(kind,'pie'), local_render_pie(ax,S.chartComp,S.otherThresh.Value);
            else, local_render_bar(ax,S.chartComp,12); end
            title(ax,'');
            try
                exportgraphics(f,fullfile(fp,fn),'Resolution',300,'BackgroundColor','white');
            catch
                set(f,'PaperPositionMode','auto');
                if endsWith(lower(fn),'.pdf'), print(f,fullfile(fp,fn),'-dpdf','-bestfit');
                else, print(f,fullfile(fp,fn),'-dpng','-r300'); end
            end
        catch ME, uialert(S.fig,ME.message,'Save failed'); end
    end

    function exportHeatmap()
        if ~S.densReady, uialert(S.fig,'Load or run an ROI first.','Heatmap'); return; end
        [fn,fp]=uiputfile({'*.png','PNG';'*.pdf','PDF'},'Export current heatmap',[S.roiSelect.Value '_heatmap.png']);
        if isequal(fn,0), return; end
        try
            renderDensity();
            % Copy only rendered axes. This preserves overlays, limits and scale
            % without exporting controls or rerunning image processing.
            f=figure('Visible','off','Color','w','Position',[100 100 1500 620]);
            cleaner=onCleanup(@()close(f));
            src=[S.sagAx S.corAx S.axAx S.cbarAx];
            pos={[.025 .16 .285 .70],[.33 .16 .285 .70],[.635 .16 .285 .70],[.94 .25 .018 .50]};
            for n=1:4
                ax=axes(f,'Units','normalized','Position',pos{n});
                copyobj(src(n).Children,ax);
                ax.XLim=src(n).XLim; ax.YLim=src(n).YLim;
                ax.XDir=src(n).XDir; ax.YDir=src(n).YDir;
                ax.DataAspectRatio=src(n).DataAspectRatio;
                ax.XTick=src(n).XTick; ax.YTick=src(n).YTick;
                ax.Color=src(n).Color;
                title(ax,'');
                if n==4
                    ax.YAxisLocation='right'; ylabel(ax,S.scale.Value);
                    ax.DataAspectRatioMode='auto';
                end
            end
            try
                exportgraphics(f,fullfile(fp,fn),'Resolution',300,'BackgroundColor','white');
            catch
                set(f,'PaperPositionMode','auto');
                if endsWith(lower(fn),'.pdf'), print(f,fullfile(fp,fn),'-dpdf','-bestfit');
                else, print(f,fullfile(fp,fn),'-dpng','-r300'); end
            end
        catch ME, uialert(S.fig,ME.message,'Export failed'); end
    end

    % ---- draw the pie + fill the percentage table from the result ------
    function showResults(~, results)
        comp = results.comp; S.chartComp=comp;
        local_render_bar(S.barAx,comp,12);
        local_render_pie(S.pieAx, comp, S.otherThresh.Value);
        S.tbl.Data = local_comp_table(comp);

        % a quick text summary of the top regions in the log
        try
            ord = comp.order;
            n = min(8, numel(ord));
            appendLog('Top regions (density-weighted):');
            for r = 1:n
                appendLog(sprintf('  %-32s %5.1f %%', ...
                    comp.region{ord(r)}, comp.densityPct(ord(r))));
            end
            appendLog(sprintf('  %-32s %5.1f %%', 'Unlabeled / outside atlas', ...
                comp.unlabeledDensityPct));
        catch
        end

        % the new orthogonal voxel-density viewer
        loadDensityView(results);
    end

    % ---- load the across-subject density map into the MNI viewer -------
    % Real runs return results.densityFile (voxel_density_MNI.nii); the demo
    % returns the volume directly in results.density/refMat/refDim.
    function loadDensityView(results)
        S.densReady = false;
        V = []; M = []; dim = [];
        try
            if isfield(results,'density') && ~isempty(results.density)
                V = results.density; M = results.refMat; dim = results.refDim;
            elseif isfield(results,'densityFile') && ~isempty(results.densityFile) ...
                    && exist(results.densityFile,'file')==2 && exist('spm_vol','file')==2
                h = mva_read_data(results.densityFile);
                V = h.img; M = h.mat; dim = h.dim;
            end
        catch ME
            appendLog(['(density view unavailable: ' ME.message ')']);
        end

        if isempty(V) || ~any(V(:) > 0)
            for axh = [S.sagAx S.corAx S.axAx], cla(axh,'reset'); axh.BackgroundColor=[0 0 0]; axh.XTick=[]; axh.YTick=[]; end
            title(S.sagAx,'Sagittal'); title(S.corAx,'Coronal'); title(S.axAx,'Axial');
            cla(S.cbarAx,'reset'); S.cbarAx.XTick=[]; S.cbarAx.YTick=[];
            S.densInfo.Text = 'Voxel-density map not available for this run.';
            return;
        end

        V(~isfinite(V)) = 0;
        S.densVol = V; S.densMat = M; S.densDim = dim; S.densMax = max(V(:));
        if isfield(results,'nSubj'), S.densSubj = results.nSubj;
        else, S.densSubj = 1; end

        % anatomical underlay: use a supplied background (e.g. the demo brain)
        % if present, otherwise resample an MNI template (needs SPM/FSL).
        S.densBg = [];
        if isfield(results,'bg') && ~isempty(results.bg) && isequal(size(results.bg), size(V))
            S.densBg = struct('img',results.bg,'mat',M);
        else
            try S.densBg = local_resample_bg(results); catch, S.densBg = []; end
        end

        % default crosshair = peak-overlap voxel
        [~, ix] = max(V(:));
        [pI,pJ,pK] = ind2sub(dim, ix);
        S.sagSld.Limits = [1 max(dim(1),2)]; S.sagSld.Value = pI;
        S.corSld.Limits = [1 max(dim(2),2)]; S.corSld.Value = pJ;
        S.axSld.Limits  = [1 max(dim(3),2)]; S.axSld.Value  = pK;

        local_draw_cbar(S.cbarAx, S.densMax);
        S.densReady = true;
        if isfield(results,'atlas') && ~isempty(results.atlas)
            S.densAtlas = results.atlas;
        else
            S.densAtlas = [];
        end
        updateContainment();   % centre of gravity + sphere/box + slices
        appendLog(sprintf('Density view ready — peak overlap = %.1f subject(s).', S.densMax));
    end

    % ---- centre of gravity + sphere/box that captures X% of the density ---
    % Recomputed only when the data or the shape/coverage dropdowns change; the
    % slice sliders just redraw (renderDensity) using the cached S.cont.
    function updateContainment()
        if ~isfield(S,'densReady') || ~S.densReady, S.cont = []; return; end
        cover = sscanf(S.contCover.Value,'%d') / 100;
        shape = lower(S.contShape.Value);
        try
            C = local_containment(S.densVol, S.densMat, cover, shape, S.densAtlas);
        catch ME
            appendLog(['(containment unavailable: ' ME.message ')']);
            S.cont = []; renderDensity(); return;
        end
        S.cont = C;
        if ~C.ok
            S.contSummary.Text = '';
            S.contList.Value = {'No voxel density available to analyse.'};
            renderDensity(); return;
        end

        % centre the crosshair/sliders on the COG so the full outline is visible
        v = round(S.densMat \ [C.cog(:); 1]);
        S.sagSld.Value = min(max(v(1),1), S.densDim(1));
        S.corSld.Value = min(max(v(2),1), S.densDim(2));
        S.axSld.Value  = min(max(v(3),1), S.densDim(3));

        S.densInside = C.inside;    % for the region-in-shape highlight fill

        rlabel = 'radius'; if strcmp(shape,'box'), rlabel = 'half-width'; end
        S.contSummary.Text = sprintf('Voxel centre (MNI) [%+.0f %+.0f %+.0f] mm    %s %s = %.1f mm  (captures %s)', ...
            C.cog(1), C.cog(2), C.cog(3), S.contShape.Value, rlabel, C.r, S.contCover.Value);

        % region % list (collapsed to top 5 + "(other)") and highlight dropdown
        lines = {sprintf('Atlas regions inside the %s  (%% of captured density):', lower(S.contShape.Value))};
        hiItems = {'(none)'}; hiData = 0;
        if isempty(C.regNames)
            lines{end+1} = '   (atlas overlap not available for this run)';
        else
            nm = C.regNames; pc = C.regPct; vv = C.regValues; topN = 5;
            if numel(nm) > topN
                dispNm = [nm(1:topN); {'(other)'}];
                dispPc = [pc(1:topN); sum(pc(topN+1:end))];
            else
                dispNm = nm; dispPc = pc;
            end
            for r = 1:numel(dispNm)
                lines{end+1} = sprintf('   %-34s %5.1f %%', dispNm{r}, dispPc(r)); %#ok<AGROW>
            end
            if ~isempty(C.cogRegion)
                lines{end+1} = '';
                lines{end+1} = sprintf('   Voxel centre lies in: %s', C.cogRegion);
            end
            for r = 1:numel(nm)                       % named regions -> dropdown
                if vv(r) > 0
                    hiItems{end+1} = sprintf('%s  (%.1f%%)', nm{r}, pc(r)); %#ok<AGROW>
                    hiData(end+1)  = vv(r);                                  %#ok<AGROW>
                end
            end
        end
        S.contList.Value = lines;

        prev = S.contHi.Value;
        S.contHi.Items = hiItems; S.contHi.ItemsData = hiData;
        if ismember(prev, hiData), S.contHi.Value = prev; else, S.contHi.Value = 0; end

        highlightChanged();     % builds the region masks and redraws the slices
    end

    % ---- draw the picked atlas region: outline + fill of the part in-shape -
    function highlightChanged()
        if ~isfield(S,'densReady') || ~S.densReady, return; end
        val = S.contHi.Value; if isempty(val), val = 0; end
        if val == 0 || isempty(S.densAtlas) || ~isfield(S.densAtlas,'labelVol')
            S.hiMask = []; S.hiInbox = [];
            % no region -> recentre the slices on the density centre of gravity
            if ~isempty(S.cont) && isfield(S.cont,'cog') && ~isempty(S.cont.cog)
                snapSlicesToWorld(S.cont.cog);
            end
        else
            S.hiMask = (S.densAtlas.labelVol == val);
            if ~isempty(S.densInside) && isequal(size(S.densInside), size(S.hiMask))
                S.hiInbox = S.hiMask & S.densInside;
            else
                S.hiInbox = [];
            end
            % jump the three slices to the region's centre so it is shown large
            % and centred (otherwise it can sit off the current slices entirely)
            idx = find(S.hiMask);
            if ~isempty(idx)
                [ri,rj,rk] = ind2sub(size(S.hiMask), idx);
                snapSlicesToVoxel(round([mean(ri) mean(rj) mean(rk)]));
            end
        end
        renderDensity();
    end

    function snapSlicesToVoxel(v)
        S.sagSld.Value = min(max(v(1),1), S.densDim(1));
        S.corSld.Value = min(max(v(2),1), S.densDim(2));
        S.axSld.Value  = min(max(v(3),1), S.densDim(3));
    end
    function snapSlicesToWorld(cogWorld)
        v = round(S.densMat \ [cogWorld(:); 1]);
        snapSlicesToVoxel(v(1:3));
    end

    % ---- redraw the three orthogonal slices at the crosshair -----------
    function renderDensity()
        if ~isfield(S,'densReady') || ~S.densReady, return; end
        dim = S.densDim; M = S.densMat; V = S.densVol;
        i = min(max(round(S.sagSld.Value),1), dim(1));
        j = min(max(round(S.corSld.Value),1), dim(2));
        k = min(max(round(S.axSld.Value), 1), dim(3));
        cross = [i j k]; cmax = max(S.densSubj, eps);
        if strcmp(S.scale.Value,'Percent'), V=100*V/S.densSubj; cmax=100; end
        local_draw_cbar(S.cbarAx,cmax); ylabel(S.cbarAx,S.scale.Value);

        cont = []; if isfield(S,'cont'), cont = S.cont; end
        hi = struct('mask',[],'inbox',[]);
        if isfield(S,'hiMask'),  hi.mask  = S.hiMask;  end
        if isfield(S,'hiInbox'), hi.inbox = S.hiInbox; end
        local_draw_view(S.sagAx, 'sag', V, S.densBg, M, cross, cmax, cont, hi);
        local_draw_view(S.corAx, 'cor', V, S.densBg, M, cross, cmax, cont, hi);
        local_draw_view(S.axAx,  'ax',  V, S.densBg, M, cross, cmax, cont, hi);

        mm = M * [i; j; k; 1];
        S.densInfo.Text=sprintf('%s | MNI [%+.0f %+.0f %+.0f] mm | %.1f %s | N=%d', ...
            S.roiSelect.Value,mm(1),mm(2),mm(3),V(i,j,k),S.scale.Value,S.densSubj);
    end
end

% ============ file-scope helpers (no shared state) =======================
% Built-in atlas presets. Paths are relative to $FSLDIR/data/atlases and are
% resolved at selection time (so the list shows even without FSL installed).
% All standard FSL label atlases use an XML lookup and hard 'maxprob' labels.
% Add your own lab atlases here (or just use "Custom" + Browse in the GUI).
function s = onoff(tf), if tf, s='on'; else, s='off'; end, end

% number of BIDS participant folders (sub-*) directly under a dataset root
function n = local_count_bids_subjects(d)
    n = 0;
    e = dir(fullfile(d,'sub-*'));
    if isempty(e), return; end
    n = sum([e.isdir]);
end

% seconds -> "MM:SS" (or "H:MM:SS" past an hour)
function s = local_mmss(sec)
    sec = max(0, round(sec));
    hh = floor(sec/3600); mm = floor(mod(sec,3600)/60); ss = mod(sec,60);
    if hh > 0
        s = sprintf('%d:%02d:%02d', hh, mm, ss);
    else
        s = sprintf('%02d:%02d', mm, ss);
    end
end

% ---- live charts drawn straight from the composition struct -------------
function local_render_pie(ax, comp, otherPct)
    cla(ax,'reset');
    ord = comp.order;
    pct = comp.densityPct(ord);
    nm  = comp.region(ord);
    big = pct >= otherPct;
    vals  = [pct(big); sum(pct(~big)) + comp.unlabeledDensityPct];
    names = [nm(big);  {'Other / unlabeled'}];
    vals  = max(vals, eps);

    % No on-slice percentage text: thin adjacent slices (small regions) make
    % those labels collide. Show each percentage in the legend instead (1 dp),
    % so nothing overlaps regardless of slice size.
    h = pie(ax, vals, repmat({''}, numel(vals), 1));
    colormap(ax, local_palette(numel(vals)));
    delete(findobj(h, 'Type', 'text'));   % drop any stray labels pie() adds
    ax.Clipping = 'off';

    legNames = arrayfun(@(i) sprintf('%s  (%.1f%%)', names{i}, vals(i)), ...
                        (1:numel(vals))', 'UniformOutput', false);
    legend(ax, legNames, 'Location','eastoutside','Interpreter','none','Box','off', ...
           'FontSize', 11);
    title(ax, sprintf('Density-weighted composition (N=%d)', comp.nSubj), ...
          'FontSize',13);
end

function local_render_bar(ax,comp,topN)
    cla(ax,'reset'); n=min(topN,numel(comp.order)); idx=comp.order(1:n);
    bar(ax,comp.meanPct(idx)); hold(ax,'on');
    errorbar(ax,1:n,comp.meanPct(idx),comp.sdPct(idx),'k','LineStyle','none','CapSize',4);
    hold(ax,'off'); ax.XTick=1:n; ax.XTickLabel=comp.region(idx);
    ax.TickLabelInterpreter='none'; xtickangle(ax,40);
    ylabel(ax,'% of voxel (per-subject mean \pm SD)'); box(ax,'off');
end

% a pleasant categorical palette (Tableau-10-ish), cycled to n colours
function cmap = local_palette(n)
    base = [ 0.121 0.466 0.705;  0.890 0.466 0.137;  0.196 0.627 0.227; ...
             0.839 0.227 0.235;  0.580 0.404 0.741;  0.549 0.337 0.294; ...
             0.890 0.467 0.760;  0.498 0.498 0.498;  0.737 0.741 0.133; ...
             0.090 0.745 0.811 ];
    cmap = base(mod(0:n-1, size(base,1)) + 1, :);
end

% ---- one orthogonal slice of the density map, hot-overlaid on anatomy ---
% kind = 'sag' | 'cor' | 'ax'. Assumes an axis-aligned (diagonal) MNI affine
% M, as produced by SPM normalise-write / the resampled atlas grid.
function local_draw_view(ax, kind, V, bg, M, cross, cmax, cont, hi)
    if nargin < 8, cont = []; end
    if nargin < 9, hi = []; end
    i = cross(1); j = cross(2); k = cross(3);
    switch kind
        case 'sag'    % fix X(i); in-plane = Y (horizontal) x Z (vertical)
            sl   = squeeze(V(i,:,:)).';                 % rows=Z, cols=Y
            bgsl = [];
            xw = M(2,2)*(1:size(V,2)) + M(2,4);          % Y world (mm)
            yw = M(3,3)*(1:size(V,3)) + M(3,4);          % Z world (mm)
            cx = M(2,2)*j + M(2,4); cy = M(3,3)*k + M(3,4);
        case 'cor'    % fix Y(j); in-plane = X (horizontal) x Z (vertical)
            sl   = squeeze(V(:,j,:)).';                 % rows=Z, cols=X
            bgsl = [];
            xw = M(1,1)*(1:size(V,1)) + M(1,4);          % X world (mm)
            yw = M(3,3)*(1:size(V,3)) + M(3,4);          % Z world (mm)
            cx = M(1,1)*i + M(1,4); cy = M(3,3)*k + M(3,4);
        otherwise     % 'ax': fix Z(k); in-plane = X (horizontal) x Y (vertical)
            sl   = squeeze(V(:,:,k)).';                 % rows=Y, cols=X
            bgsl = [];
            xw = M(1,1)*(1:size(V,1)) + M(1,4);          % X world (mm)
            yw = M(2,2)*(1:size(V,2)) + M(2,4);          % Y world (mm)
            cx = M(1,1)*i + M(1,4); cy = M(2,2)*j + M(2,4);
    end

    % highlighted atlas-region slices (same orientation as sl): full region rs,
    % and the part inside the containment shape isb.
    rs = []; isb = []; pr = [];
    if ~isempty(hi) && isfield(hi,'mask') && ~isempty(hi.mask)
        fd = fixdim_(kind);
        rs = local_bgslice(hi.mask, fd, cross(fd));
        pr = squeeze(any(hi.mask, fd)).';          % full-region footprint (MIP)
        if isfield(hi,'inbox') && ~isempty(hi.inbox)
            isb = local_bgslice(hi.inbox, fd, cross(fd));
        end
    end

    % orient axes ascending (so labels/crosshair read in real mm)
    if numel(xw) > 1 && xw(1) > xw(end)
        xw = fliplr(xw); sl = fliplr(sl);
        if ~isempty(bgsl), bgsl = fliplr(bgsl); end
        if ~isempty(rs),  rs  = fliplr(rs);  end
        if ~isempty(isb), isb = fliplr(isb); end
        if ~isempty(pr),  pr  = fliplr(pr);  end
    end
    if numel(yw) > 1 && yw(1) > yw(end)
        yw = fliplr(yw); sl = flipud(sl);
        if ~isempty(bgsl), bgsl = flipud(bgsl); end
        if ~isempty(rs),  rs  = flipud(rs);  end
        if ~isempty(isb), isb = flipud(isb); end
        if ~isempty(pr),  pr  = flipud(pr);  end
    end

    % Display density with nearest-neighbour replication only. Its original
    % values and cell boundaries remain intact; anatomy is sampled separately.
    [ny0,nx0]=size(sl);
    if nx0>1 && ny0>1
        factor=max(2,ceil(900/max(nx0,ny0)));
        nxq=nx0*factor; nyq=ny0*factor;
        qx=0.5+((1:nxq)-0.5)/factor;
        qy=0.5+((1:nyq)-0.5)/factor;
        [XI,YI]=meshgrid(min(max(qx,1),nx0),min(max(qy,1),ny0));
        sl=interp2(sl,XI,YI,'nearest',0);
        if ~isempty(rs), rs=interp2(double(rs),XI,YI,'nearest',0); end
        if ~isempty(isb), isb=interp2(double(isb),XI,YI,'nearest',0); end
        if ~isempty(pr), pr=interp2(double(pr),XI,YI,'nearest',0); end
        xw=xw(1)+(qx-1)*(xw(2)-xw(1));
        yw=yw(1)+(qy-1)*(yw(2)-yw(1));
    end
    if ~isempty(bg)
        world=M*[cross(:);1]; fd=fixdim_(kind);
        bgsl=mva_background_slice(bg,kind,world(fd),xw,yw);
        bgsl=local_contrast_stretch(bgsl);
    end

    % build a truecolor image: grayscale anatomy + hot density overlay
    dn  = min(max(sl / cmax, 0), 1);
    hm  = local_hotmap(256);
    idx = round(dn*255) + 1;
    ov  = reshape(hm(idx(:),:), [size(dn) 3]);
    if ~isempty(bgsl)
        g = double(bgsl); rng = max(g(:)) - min(g(:));
        if rng > 0, g = (g - min(g(:))) / rng; else, g = zeros(size(g)); end
        base = repmat(g, [1 1 3]);
    else
        base = zeros([size(dn) 3]);
    end
    % zero density -> transparent (brain shows through); cap below 1 so the
    % anatomy stays faintly visible even under the hottest peak voxels.
    amax = 0.92; if isempty(bgsl), amax = 1; end
    a   = repmat(min(sqrt(dn), amax), [1 1 3]);

    % when a region is highlighted, fade the density right back so the region
    % reads in isolation over the anatomy (rather than under the hot colours).
    regionShown = ~isempty(rs) && any(rs(:) > 0.5);
    if regionShown, a = a * 0.18; end
    rgb = base.*(1-a) + ov.*a;

    if regionShown
        % the FULL atlas region, painted solid (orange) so its exact extent
        % and shape are unmistakable on the anatomy.
        AR  = repmat(0.55 * double(rs > 0.5), [1 1 3]);
        ORG = repmat(reshape([1.00 0.52 0.10], 1, 1, 3), size(rs,1), size(rs,2));
        rgb = rgb.*(1-AR) + ORG.*AR;
        % the part of that region INSIDE the sphere/box, painted brighter yellow
        if ~isempty(isb) && any(isb(:) > 0.5)
            AI = repmat(0.85 * double(isb > 0.5), [1 1 3]);
            YL = repmat(reshape([1.00 0.95 0.35], 1, 1, 3), size(isb,1), size(isb,2));
            rgb = rgb.*(1-AI) + YL.*AI;
        end
    end

    cla(ax,'reset');
    image(ax, xw, yw, rgb);
    set(ax,'YDir','normal'); axis(ax,'image');
    % radiological convention (subject's left on image right) for the axial &
    % coronal planes, matching the reference figure.
    if ~strcmp(kind,'sag'), set(ax,'XDir','reverse'); end
    ax.XTick = []; ax.YTick = []; ax.Color = [0 0 0];
    ax.XColor = [0.5 0.5 0.5]; ax.YColor = [0.5 0.5 0.5];
    hold(ax,'on');
    plot(ax, [cx cx], yw([1 end]), 'Color',[0.2 1 0.4], 'LineWidth',0.5);
    plot(ax, xw([1 end]), [cy cy], 'Color',[0.2 1 0.4], 'LineWidth',0.5);

    % containment outline: cross-section of the sphere/box through this slice,
    % centred on the density's centre of gravity (all in world mm).
    if ~isempty(cont) && isfield(cont,'ok') && cont.ok
        switch kind
            case 'sag'                       % fixed X = slice; in-plane = Y,Z
                ip = [cont.cog(2) cont.cog(3)]; fixW = M(1,1)*i + M(1,4); fc = cont.cog(1);
            case 'cor'                       % fixed Y = slice; in-plane = X,Z
                ip = [cont.cog(1) cont.cog(3)]; fixW = M(2,2)*j + M(2,4); fc = cont.cog(2);
            otherwise                        % 'ax': fixed Z = slice; in-plane = X,Y
                ip = [cont.cog(1) cont.cog(2)]; fixW = M(3,3)*k + M(3,4); fc = cont.cog(3);
        end
        d = abs(fixW - fc); col = [0.20 0.80 1.00];
        if strcmpi(cont.shape,'box')
            if d <= cont.r + 1e-6
                h = cont.r;
                plot(ax, ip(1)+[-h h h -h -h], ip(2)+[-h -h h h -h], ...
                    'Color',col, 'LineWidth',1.5);
            end
        else
            if d < cont.r
                rr = sqrt(max(cont.r^2 - d^2, 0)); th = linspace(0,2*pi,144);
                plot(ax, ip(1)+rr*cos(th), ip(2)+rr*sin(th), 'Color',col, 'LineWidth',1.5);
            end
        end
    end

    % full-region footprint (projection through the slab): dotted, so the
    % region's whole extent/location is visible even off its centre slice
    if ~isempty(pr) && any(pr(:) > 0.5)
        try
            [~, hp] = contour(ax, xw, yw, pr, [0.5 0.5]);
            hp.LineColor = [1 0.60 0.15]; hp.LineWidth = 0.8; hp.LineStyle = ':';
        catch
        end
    end
    % highlighted atlas-region boundary (yellow) on this slice
    if ~isempty(rs) && any(rs(:) > 0.5)
        try
            [~, hc] = contour(ax, xw, yw, rs, [0.5 0.5]);
            hc.LineColor = [1 0.92 0.25]; hc.LineWidth = 1.3;
        catch
        end
    end
    hold(ax,'off');

    % anatomical orientation labels (white, at the edges). The 'R' marker sits
    % at +X (right hemisphere); under XDir-reverse it renders on image-left.
    switch kind
        case 'sag', local_edgelabels(ax, xw, yw, 'A','P','S','I');
        case 'cor', local_edgelabels(ax, xw, yw, 'R','L','S','I');
        otherwise,  local_edgelabels(ax, xw, yw, 'R','L','A','P');
    end
    titles = struct('sag','Sagittal','cor','Coronal','ax','Axial');
    title(ax, titles.(kind), 'Color',[0.15 0.18 0.22]);
end

% ---- centre of gravity + smallest sphere/box capturing `coverage` of density
% V        density volume; M 4x4 voxel->world (mm) affine
% coverage fraction in (0,1]; shape 'sphere' | 'box'
% atlas    struct with .labelVol (same grid), .values, .name  (or [] to skip)
% Returns C with: ok, cog [1x3 mm], r (mm; sphere radius or box half-width),
% shape, plus regNames/regPct (atlas regions inside, % of captured density,
% top 5 + "(other)") and cogRegion (atlas region at the COG).
function C = local_containment(V, M, coverage, shape, atlas)
    C = struct('ok',false,'cog',[0 0 0],'r',0,'shape',shape,'coverage',coverage, ...
               'regNames',{{}},'regPct',[],'regValues',[],'cogRegion','','inside',[]);
    V = double(V); V(~isfinite(V) | V < 0) = 0;
    tot = sum(V(:));
    if tot <= 0, return; end
    dim = size(V);

    [I,J,K] = ndgrid(1:dim(1), 1:dim(2), 1:dim(3));
    Xw = M(1,1)*I + M(1,2)*J + M(1,3)*K + M(1,4);
    Yw = M(2,1)*I + M(2,2)*J + M(2,3)*K + M(2,4);
    Zw = M(3,1)*I + M(3,2)*J + M(3,3)*K + M(3,4);
    w = V(:); Xw = Xw(:); Yw = Yw(:); Zw = Zw(:);

    % Centre on the MRS voxel itself: the centroid of its coreg-derived body
    % (the footprint at >= 50% of peak overlap), NOT the partial-volume /
    % overlap-weighted COG. Soft warped voxel edges bias the weighted COG off
    % the true voxel centre; the half-max body centroid lines the box up with
    % Osprey's original voxel.
    pk = max(w);
    core = w >= 0.5*pk; if ~any(core), core = w > 0; end
    cw0 = double(core);
    cog = [sum(cw0.*Xw); sum(cw0.*Yw); sum(cw0.*Zw)] / sum(cw0);
    dx = Xw - cog(1); dy = Yw - cog(2); dz = Zw - cog(3);
    if strcmpi(shape,'box')
        dist = max(max(abs(dx),abs(dy)), abs(dz));      % Chebyshev -> cube
    else
        dist = sqrt(dx.^2 + dy.^2 + dz.^2);             % Euclidean -> sphere
    end

    % grow the region from the COG until it captures `coverage` of the density
    pos = w > 0;
    [ds, si] = sort(dist(pos));
    ww = w(pos); ww = ww(si);
    cw = cumsum(ww);
    idx = find(cw >= coverage*tot - 1e-9, 1, 'first');
    if isempty(idx), r = ds(end); else, r = ds(idx); end
    C.ok = true; C.cog = cog(:).'; C.r = r; C.shape = shape;

    inside = dist <= r + 1e-9;
    C.inside = reshape(inside, dim);            % 3D logical, for the region fill

    % atlas overlap inside the containment region (full sorted list; the GUI
    % collapses it to top-N + "(other)" for display and builds the dropdown).
    if ~isempty(atlas) && isstruct(atlas) && isfield(atlas,'labelVol') ...
            && isequal(size(atlas.labelVol), dim)
        cap = sum(w(inside));
        if cap > 0
            lab  = double(atlas.labelVol(:));
            allV = [atlas.values(:).', 0];       % append 0 = unlabeled
            pct  = zeros(numel(allV),1); nm = cell(numel(allV),1);
            for m = 1:numel(allV)
                v = allV(m);
                pct(m) = 100 * sum(w(inside & lab==v)) / cap;
                if v == 0,                    nm{m} = 'Unlabeled / outside atlas';
                elseif isKey(atlas.name, v),  nm{m} = atlas.name(v);
                else,                         nm{m} = sprintf('label %d', v); end
            end
            keep = pct > 0.05;
            pct = pct(keep); nm = nm(keep); allV = allV(keep);
            [pct, o] = sort(pct,'descend');
            C.regNames = nm(o); C.regPct = pct(:); C.regValues = allV(o).';

            cv = round(M \ [cog; 1]); cv = max(min(cv(1:3), dim(:)), [1;1;1]);
            lv = atlas.labelVol(cv(1),cv(2),cv(3));
            if lv > 0 && isKey(atlas.name, lv), C.cogRegion = atlas.name(lv);
            elseif lv > 0, C.cogRegion = sprintf('label %d', lv);
            else, C.cogRegion = 'Unlabeled / outside atlas'; end
        end
    end
end

% map a view kind to the volume dimension held fixed in that plane
function d = fixdim_(kind)
    switch kind
        case 'sag', d = 1;
        case 'cor', d = 2;
        otherwise,  d = 3;
    end
end

% pull a 2-D anatomy slice matching local_draw_view's in-plane orientation
function bgsl = local_bgslice(bg, fixDim, idx)
    bgsl = [];
    if isempty(bg), return; end
    switch fixDim
        case 1, bgsl = squeeze(bg(idx,:,:)).';
        case 2, bgsl = squeeze(bg(:,idx,:)).';
        case 3, bgsl = squeeze(bg(:,:,idx)).';
    end
end

% robust contrast stretch for the anatomy underlay: clip to the 1st/99th
% intensity percentiles (ignoring the air background) and rescale to [0,1].
% This lifts the low-contrast brain detail so the sagittal/coronal anatomy
% reads crisply. Toolbox-free (no prctile). Returns values in [0,1].
function out = local_contrast_stretch(img)
    out = double(img);
    v = out(out > 0);                  % drop air/background zeros
    if numel(v) < 2
        m = max(out(:));
        if m > 0, out = out / m; end
        return;
    end
    v = sort(v(:));
    lo = v(max(1, round(0.01*numel(v))));
    hi = v(max(1, round(0.99*numel(v))));
    if hi <= lo, hi = v(end); lo = v(1); end
    if hi <= lo, out = zeros(size(out)); return; end
    out = (out - lo) / (hi - lo);
    out = min(max(out, 0), 1);
end

% place R/L/A/P/S/I markers (right, left, top, bottom of the ascending axes)
function local_edgelabels(ax, xw, yw, rightTxt, leftTxt, topTxt, botTxt)
    xr = xw([1 end]); yr = yw([1 end]);
    txt = @(x,y,s) text(ax, x, y, s, 'Color',[1 1 1], 'FontSize',9, ...
        'FontWeight','bold', 'HorizontalAlignment','center', ...
        'VerticalAlignment','middle', 'Clipping','off');
    txt(xr(2), mean(yr), rightTxt);
    txt(xr(1), mean(yr), leftTxt);
    txt(mean(xr), yr(2), topTxt);
    txt(mean(xr), yr(1), botTxt);
end

% hot-style colormap (black -> red -> yellow -> white) without toolbox deps
function cm = local_hotmap(n)
    if nargin < 1, n = 256; end
    r = min(1, linspace(0,1,n)*3);
    g = min(1, max(0, linspace(0,1,n)*3 - 1));
    b = min(1, max(0, linspace(0,1,n)*3 - 2));
    cm = [r(:) g(:) b(:)];
end

% vertical "Number of subjects" colourbar (0 -> peak overlap), hot colormap,
% matching the reference figure's scale bar.
function local_draw_cbar(ax, cmax)
    cla(ax,'reset');
    cmax = max(cmax, eps);
    strip = reshape(local_hotmap(256), [256 1 3]);
    image(ax, [0 1], [0 cmax], strip);
    set(ax,'YDir','normal');
    ax.XTick = []; ax.XLim = [0 1];
    ax.YLim = [0 cmax];
    ax.YAxisLocation = 'right';
    ax.YTick = unique(round([0 cmax/2 cmax]));
    ax.YColor = [0.15 0.18 0.22]; ax.Box = 'on';
    ylabel(ax, 'Number of subjects', 'Color',[0.15 0.18 0.22], 'FontSize',11);
    ax.DataAspectRatioMode = 'auto'; ax.PlotBoxAspectRatioMode = 'auto';
end

% Load MNI anatomy on its own grid; display sampling uses its world affine.
function bg = local_resample_bg(results)
    % Use avg305T1 from the user's configured SPM installation.
    spmDir = '';

    if isfield(results,'cfg') && isfield(results.cfg,'spmPath')
        spmDir = results.cfg.spmPath;
    end

    if isempty(spmDir) && exist('spm','file') == 2
        spmDir = spm('Dir');
    end

    assert(~isempty(spmDir), ...
        'Set the SPM12 folder in Advanced settings.');

    tmpl = fullfile(spmDir, 'canonical', 'avg152T1.nii');

    assert(isfile(tmpl), ...
        'SPM background image not found: %s', tmpl);

    bg = mva_read_data(tmpl);
end

% Locate an MNI T1 template (.nii or .nii.gz; SPM canonical preferred).
function t = local_find_template()
    t = ''; cands = {};
    if exist('spm','file')==2
        d = spm('Dir');
        cands{end+1} = fullfile(d,'canonical','single_subj_T1.nii');
        cands{end+1} = fullfile(d,'canonical','avg152T1.nii');
    end
    f = getenv('FSLDIR');
    if ~isempty(f)
        cands{end+1} = fullfile(f,'data','standard','MNI152_T1_1mm_brain.nii');
        cands{end+1} = fullfile(f,'data','standard','MNI152_T1_1mm.nii');
    end
    for ii = 1:numel(cands)
        if exist(cands{ii},'file')==2, t = cands{ii}; return; end
        if isfile([cands{ii} '.gz']), t=[cands{ii} '.gz']; return; end
    end
end

% ---- percentages as a numeric table (region-sorted, descending) --------
function C = local_comp_table(comp)
    fmt = @(x) sprintf('%.1f', x);
    ord = comp.order;
    n   = numel(ord);
    C   = cell(n+1, 4);
    for r = 1:n
        i = ord(r);
        C{r,1} = comp.region{i};
        C{r,2} = fmt(comp.densityPct(i));
        C{r,3} = fmt(comp.meanPct(i));
        C{r,4} = fmt(comp.sdPct(i));
    end
    C{n+1,1} = 'Unlabeled / outside atlas';
    C{n+1,2} = fmt(comp.unlabeledDensityPct);
    C{n+1,3} = fmt(comp.unlabeledMeanPct);
    C{n+1,4} = '';
end

% ---- demo run: synthesize a cohort + toy atlas, compute composition -----
% Exercises steps 4-6 + reporting with NO SPM/Osprey/data. If SPM happens to
% be on the path it also writes the usual NIfTI/CSV/PNG outputs.
function results = local_run_demo(cfg, logfn)
    logfn('Demo mode: synthesizing 8 patients over a 5-region toy atlas …');
    logfn('Loading MNI152 1 mm anatomical template (downloaded & cached on first run)…');
    [density, masks, atlas, refMat, refDim, bg] = local_demo_data();
    cfg.atlasMode = atlas.mode;
    comp = mva_compute_composition(density, masks, atlas, cfg);

    if exist('spm_vol','file')==2 && exist('spm_write_vol','file')==2
        try
            mva_report(comp, density, refMat, refDim, cfg);
            logfn(sprintf('SPM found — wrote compressed NIfTI/CSV outputs to %s', cfg.outDir));
        catch e
            logfn(['(skipped writing report files: ' e.message ')']);
        end
    else
        logfn('SPM not on path — showing live charts only (no files written).');
    end

    results = struct('cfg',cfg,'comp',comp,'atlasMode',atlas.mode, ...
                     'nSubj',numel(masks),'demo',true, ...
                     'density',density,'refMat',refMat,'refDim',refDim,'bg',bg, ...
                     'atlas',struct('labelVol',atlas.labelVol,'values',atlas.values, ...
                                    'name',atlas.name,'mode',atlas.mode));
end

function [density, masks, atlas, refMat, refDim, bg] = local_demo_data()
    % Background brain: a real high-resolution MNI152 1 mm T1 template (the
    % same standard space Osprey/SPM/FSL use) so the axial, sagittal AND
    % coronal views are all sharp, realistic anatomy -- matching an Osprey
    % coregistration figure. local_demo_brain fetches/caches it (or returns a
    % synthetic isotropic phantom offline) along with its world affine.
    [bg, bgMat] = local_demo_brain();
    if ~isempty(bg)
        refDim = size(bg); vx = 1;             % isotropic 1 mm grid
        shells = [58 42 28 16]; offT = 24; offR = 70; hsz = [15 15 15]; jit = 6;
    else
        refDim = [50 60 50]; vx = 2;           % isotropic 2 mm fallback grid
        shells = [20 15 10 5];  offT = 8;  offR = 24; hsz = [6 6 6];   jit = 5;
        bgMat = [];
    end

    c = (refDim + 1)/2;
    [X,Y,Z] = ndgrid(1:refDim(1), 1:refDim(2), 1:refDim(3));
    rad = sqrt((X-c(1)).^2 + (Y-c(2)).^2 + (Z-c(3)).^2);

    if isempty(bg)   % synthetic soft ellipsoid (only when no real MRI)
        erad = sqrt(((X-c(1))/1.05).^2 + ((Y-c(2))/1.25).^2 + ((Z-c(3))/1.05).^2);
        bg = max(1 ./ (1 + exp((erad-22)/1.5)) .* (0.78 + 0.22*cos(erad/3)), 0);
    end

    % concentric toy regions + one off-centre region (labels 1..5)
    A = zeros(refDim);
    A(rad <= shells(1)) = 4;
    A(rad <= shells(2)) = 3;
    A(rad <= shells(3)) = 2;
    A(rad <= shells(4)) = 1;
    A(X > c(1)+offT & rad <= offR) = 5;

    values = (1:5)';
    names  = containers.Map('KeyType','double','ValueType','char');
    names(1) = 'Thalamus (demo)';
    names(2) = 'Putamen (demo)';
    names(3) = 'Pallidum (demo)';
    names(4) = 'White matter (demo)';
    names(5) = 'Cortex (demo)';
    atlas.labelVol = A;
    atlas.values   = values;
    atlas.name     = names;
    atlas.mode     = 'maxprob';

    % 8 patients: a rectangular MRS voxel "box" (like a real single-voxel MRS
    % placement) centred in the brain and jittered a little per subject.
    % Summing the boxes makes a solid high-overlap core that fades at the
    % edges -- exactly the layered box in the reference figure.
    nS = 8; boxc = round(c);
    masks = cell(nS,1);
    density = zeros(refDim);
    rng(42);  % reproducible demo
    for s = 1:nS
        off = round((rand(1,3) - 0.5) * jit);
        cc  = boxc + off;
        m  = zeros(refDim);
        xi = max(1,cc(1)-hsz(1)):min(refDim(1),cc(1)+hsz(1));
        yi = max(1,cc(2)-hsz(2)):min(refDim(2),cc(2)+hsz(2));
        zi = max(1,cc(3)-hsz(3)):min(refDim(3),cc(3)+hsz(3));
        m(xi,yi,zi) = 1;
        masks{s} = m;
        density  = density + m;
    end

    % use the template's real world affine when available (so the crosshair
    % shows true MNI mm); otherwise a simple centred isotropic grid.
    if ~isempty(bgMat)
        refMat = bgMat;
    else
        refMat = [vx 0 0 -c(1)*vx; 0 vx 0 -c(2)*vx; 0 0 vx -c(3)*vx; 0 0 0 1];
    end
end

% Anatomical underlay for the demo. To look like a real Osprey coregistration
% figure we use a genuine high-resolution MNI152 1 mm T1 template (the standard
% space Osprey/SPM/FSL all use) -- sharp, realistic anatomy in axial, sagittal
% AND coronal. The template is taken from SPM/FSL if on the path, otherwise
% fetched once from TemplateFlow and cached. Returns the volume (normalised to
% [0,1]) and its world affine M. Falls back to a synthetic isotropic phantom
% (M = []) only when no template can be obtained (e.g. offline).
function [bg, M] = local_demo_brain()
    M = [];
    nii = local_get_mni_template();
    if ~isempty(nii)
        try
            if exist('niftiread','file')==2
                V = double(niftiread(nii));
                info = niftiinfo(nii);
                M = info.Transform.T.';          % MATLAB row-vec affine -> column
            elseif exist('spm_vol','file')==2
                h = mva_read_data(nii); V=h.img; M=h.mat;
            else
                error('no NIfTI reader');
            end
            V(~isfinite(V)) = 0;
            mx = max(V(:)); if mx > 0, V = V / mx; end
            bg = V;
            return;
        catch
            M = [];                              % fall through to the phantom
        end
    end
    bg = local_synth_brain();                    % offline fallback (M stays [])
end

% Locate an MNI152 1 mm T1 NIfTI: prefer one already provided by SPM/FSL, else
% reuse a cached download, else fetch it once from TemplateFlow into a cache
% folder. Returns '' if none is available (e.g. offline with no SPM/FSL).
function nii = local_get_mni_template()
    nii = '';
    % 1) already on the system via SPM/FSL
    t = local_find_template();
    if ~isempty(t) && exist(t,'file')==2, nii = t; return; end
    % 2) cached from a previous download
    cacheDir = fullfile(tempdir, 'mrs_atlas_tpl');
    cached   = fullfile(cacheDir, 'MNI152_T1_1mm.nii');
    if exist(cached,'file')==2, nii = cached; return; end
    % 3) fetch once from TemplateFlow (needs internet + niftiread/gunzip)
    if exist('websave','file')~=2 || exist('gunzip','file')~=2, return; end
    url = ['https://templateflow.s3.amazonaws.com/tpl-MNI152NLin2009cAsym/' ...
           'tpl-MNI152NLin2009cAsym_res-01_T1w.nii.gz'];
    try
        if exist(cacheDir,'dir')~=7, mkdir(cacheDir); end
        gz = fullfile(cacheDir, 'MNI152_T1_1mm.nii.gz');
        websave(gz, url, weboptions('Timeout', 60));
        gunzip(gz, cacheDir);
        d = dir(fullfile(cacheDir, '*.nii'));
        if ~isempty(d)
            src = fullfile(cacheDir, d(1).name);
            if ~strcmp(src, cached), movefile(src, cached); end
            nii = cached;
        end
    catch
        nii = '';
    end
end

% Synthetic isotropic T1-style brain phantom -- the offline fallback when no
% real MNI template can be obtained. Equally crisp in all three planes.
% Base MATLAB only (no toolboxes/data); never returns [].
function bg = local_synth_brain()
    dim = [140 168 140];                         % L-R, A-P, S-I : 1 mm isotropic
    c   = (dim + 1) / 2;
    [X,Y,Z] = ndgrid(1:dim(1), 1:dim(2), 1:dim(3));
    x = X - c(1);  y = Y - c(2);  z = Z - c(3);

    % gyral folding field -- a smooth 3-D ripple that carves sulci/gyri into
    % the cortical surface, giving real, isotropic detail in every plane.
    gyri = sin(x/3.2).*sin(y/3.4) + sin(y/3.0).*sin(z/3.6) + sin(x/3.8).*sin(z/3.2);

    % ellipsoidal brain envelope (slightly longer front-to-back), with the
    % folding modulating the boundary so the cortex is convoluted, not smooth.
    ax = 60; by = 76; cz = 62;
    R  = sqrt((x/ax).^2 + (y/by).^2 + (z/cz).^2);
    brain = R <= 1 + 0.03*gyri;

    bg = zeros(dim);
    bg(brain) = 0.72;                            % white matter (bright on T1)

    % cortical gray-matter ribbon just inside the folded outer surface
    ribbon = brain & (R > 0.82 + 0.03*gyri);
    bg(ribbon) = 0.50;

    % deep gray nuclei: a symmetric pair of ellipsoids flanking the midline
    for sgn = [-1 1]
        nuc = sqrt(((x - sgn*15)/12).^2 + (y/16).^2 + (z/12).^2) <= 1;
        bg(nuc) = 0.58;
    end

    % lateral ventricles: dark CSF crescents either side of the midline
    for sgn = [-1 1]
        vent = sqrt(((x - sgn*6)/4).^2 + (y/24).^2 + ((z+2)/15).^2) <= 1;
        bg(vent) = 0.12;
    end

    % faint isotropic texture so flat tissue isn't dead-flat under contrast
    bg = bg .* (0.94 + 0.06*sin(x/2.5).*sin(y/2.5).*sin(z/2.5));
    bg = min(max(bg, 0), 1);
end

function lines = local_readlines(file)
    lines = {};
    fid = fopen(file,'r');
    if fid<0, return; end
    c = onCleanup(@() fclose(fid));
    raw = fread(fid,'*char')';
    raw = strrep(raw, char(13), '');
    lines = strsplit(raw, newline);
    lines = lines(:);
    if ~isempty(lines) && isempty(lines{end}), lines(end) = []; end
end

function local_reveal(folder)
    if ispc
        winopen(folder);
    elseif ismac
        system(['open "' folder '"']);
    else
        system(['xdg-open "' folder '" &']);
    end
end
