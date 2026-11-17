function results = run_mrs_atlas_composition(cfg)
% For a cohort of single-voxel MRS boxes that have been placed and
% coregistered with Osprey, compute what percentage of the voxel falls in
% each region of a brain atlas. Implements the workflow from the reference
% figure:
%
%   1. Input ............ T1 + MRS voxel        (OspreyJob / OspreyLoad)
%   2. Coregister ....... binary voxel mask in native T1 space (OspreyCoreg)
%   3. Normalize to MNI . warp each native mask into MNI space (SPM12)
%   4. Overlap voxels ... sum the warped masks -> voxel-density map
%   5. Overlay w/ atlas . load an atlas in MNI space, align to the grid
%   6. Composition ...... % of density / % per subject in each atlas region
%
% USAGE
%   results = run_mrs_atlas_composition(cfg)
%
% REQUIRED cfg (provide ONE source of Osprey results):
%   cfg.bidsDir      - path to a BIDS dataset folder (Osprey reads it; the GUI
%                      uses this). Runs OspreyJob+Load+Coreg(+Seg).
%   cfg.MRSCont      - Osprey MRSCont struct (with .coreg already populated)
%   cfg.mrscontMat   - path to a saved MRSCont .mat
%   cfg.jobFile      - path to an Osprey job (.m/.csv); Load+Coreg(+Seg) run
%
% REQUIRED cfg (atlas):
%   cfg.atlasImage   - atlas LABEL image (.nii or .nii.gz), e.g.
%                      HarvardOxford-sub-maxprob-thr25-1mm.nii.gz
%   cfg.atlasXML     - FSL atlas .xml (value<->name)        ... OR
%   cfg.atlasLUT     - CSV with columns value,name (any atlas)
%   cfg.outDir       - output folder
%
% OPTIONAL cfg (defaults in brackets):
%   cfg.normMethod   - 'unified' [def] (SPM seg-normalise, SPM-MNI) or
%                      'oldnorm' (to cfg.normTemplate, exact FSL-MNI)
%   cfg.normTemplate - template for 'oldnorm' [FSL MNI152_T1_1mm if $FSLDIR]
%   cfg.outVox       - output voxel size mm        [ [1 1 1] ]
%   cfg.outBB        - output bounding box mm       [ [-78 -112 -70;78 76 85] ]
%   cfg.atlasMode    - 'maxprob' [def] or 'prob'
%   cfg.maskInterp   - interpolation for warping the mask [1 = trilinear/PV]
%   cfg.maskThresh   - [] keep partial volume [def]; or e.g. 0.5 to binarize
%   cfg.otherThreshPct - pie: group slices below this % as "Other" [2]
%   cfg.topN         - bar: number of regions shown [12]
%   cfg.runSeg       - also run OspreySeg (GM/WM/CSF) when explicitly requested [false]
%   cfg.spmPath      - SPM12 path (added to path if given)
%   cfg.ospreyPath   - Osprey path (added to path if given)
%   cfg.force        - recompute warped masks/deformations even if present [false]
%
% OUTPUT
%   results struct, plus files in cfg.outDir (see mva_report).

    if isfield(cfg,'bidsDir') && ~isempty(cfg.bidsDir) && ...
            ~isfield(cfg,'MRSCont') && ~isfield(cfg,'mrscontMat') && ~isfield(cfg,'jobFile')
        results = mva_run_bids(cfg); return;
    end

    % ---- 0. setup ------------------------------------------------------
    cfg = local_defaults(cfg);
    if ~isempty(cfg.spmPath),    addpath(cfg.spmPath);            end
    if ~isempty(cfg.ospreyPath), addpath(genpath(cfg.ospreyPath)); end
    if exist('spm','file') ~= 2
        error('mva:noSPM','SPM12 not found on the path. Set cfg.spmPath.');
    end
    if ~exist(cfg.outDir,'dir'), mkdir(cfg.outDir); end
    spm('defaults','fmri');
    spm_jobman('initcfg');

    % ---- 1-2. Osprey container with coreg done (Input + Coregister) ----
    MRSCont = local_get_mrscont(cfg);
    nS = numel(MRSCont.coreg.vol_mask);
    fprintf('[mva] %d datasets with coregistered voxel masks.\n', nS);

    % ---- 3. warp every native mask into MNI (Normalize to MNI) ---------
    % cfg.progressFcn (optional) is called as progressFcn(done, total) before
    % the loop (done=0) and after each subject, so a GUI can show an ETA.
    if ~isempty(cfg.progressFcn), cfg.progressFcn(0, nS); end
    warpedPaths = {}; nativePaths = {}; ids = {}; failed = {};
    for kk = 1:nS
        id = sprintf('subject-%03d',kk);
        if isfield(cfg,'subjectIDs'), id=cfg.subjectIDs{kk}; end
        try
            mask = local_get_mask(MRSCont, kk);
            T1 = local_get_t1(MRSCont, kk);
            sd=fullfile(cfg.outDir,id); if ~isfolder(sd), mkdir(sd); end
            wcfg=cfg; wcfg.mniMaskPath=fullfile(sd,'voxel_MNI.nii.gz');
            wpath=mva_warp_voxel_to_mni(T1,mask,wcfg);
            v=mva_read_data(wpath); w=v.img;
            assert(any(isfinite(w(:)) & w(:)>=cfg.maskThresh),'Empty MNI voxel mask.');
            % The Osprey native mask is the canonical native localisation cache.
            warpedPaths{end+1,1}=wpath; nativePaths{end+1,1}=mask; ids{end+1,1}=id;
            % Remove only known duplicates made by the previous toolbox version.
            for legacy={'voxel_native.nii','voxel_native.nii.gz','wvoxel_native.nii','wvoxel_native.nii.gz','wvoxel_native.nii.mat','native_source.mat'}
                oldPath=fullfile(sd,legacy{1});
                if isfile(oldPath) && ~strcmp(oldPath,mask) && ~strcmp(oldPath,T1)
                    try, delete(oldPath); catch ME, warning('mva:cleanup','%s',ME.message); end
                end
            end
        catch ME
            failed(end+1,:)={id,ME.message}; %#ok<AGROW>
            warning('mva:warpFailed','%s: %s',id,ME.message);
        end
        if ~isempty(cfg.progressFcn), cfg.progressFcn(kk,nS); end
    end
    if ~isempty(failed)
        writetable(cell2table(failed,'VariableNames',{'Subject','Error'}),fullfile(cfg.outDir,'failed_subjects.csv'));
    end
    nS=numel(warpedPaths);
    assert(nS>0,'No subjects successfully normalised.');
    cfg.subjectIDs=ids;

    % ---- 4. overlap -> voxel-density map (Overlap Voxels) --------------
    h0     = mva_read_data(warpedPaths{1});
    refMat = h0.mat;
    refDim = h0.dim(1:3);
    warpedMasks = cell(nS,1);
    density     = zeros(refDim);
    centres = zeros(nS,3);
    for kk = 1:nS
        h = mva_read_data(warpedPaths{kk});
        if ~isequal(h.dim(1:3), refDim) || max(abs(h.mat(:)-refMat(:)))>1e-5
            error('mva:gridMismatch', ...
                'Warped mask %d is on a different grid than mask 1.', kk);
        end
        w = h.img;
        w(~isfinite(w)) = 0;
        if ~isempty(cfg.maskThresh)
            w = double(w >= cfg.maskThresh);
        end
        assert(any(w(:)>0),'Empty mask after thresholding.');
        idx=find(w>0); [xx,yy,zz]=ind2sub(refDim,idx); weights=w(idx);
        centre=refMat*[sum(xx.*weights);sum(yy.*weights);sum(zz.*weights);sum(weights)]/sum(weights);
        centres(kk,:)=centre(1:3)';
        warpedMasks{kk} = w;
        density = density + w;
    end

    % ---- 5. load atlas & align to the grid (Overlay with Atlas) -------
    atlas = mva_load_atlas(cfg, refMat, refDim);

    % ---- 6. composition (Calculate Composition) -----------------------
    comp = mva_compute_composition(density, warpedMasks, atlas, cfg);

    roi='ROI'; if isfield(cfg,'roi'), roi=cfg.roi; end
    locations=table(ids,repmat({roi},nS,1),centres(:,1),centres(:,2),centres(:,3),nativePaths,warpedPaths, ...
        'VariableNames',{'Subject','ROI','X','Y','Z','NativeMask','MNIMask'});
    writetable(locations,fullfile(cfg.outDir,'voxel_centres_MNI.csv'));

    % ---- output -------------------------------------------------------
    mva_report(comp, density, refMat, refDim, cfg);

    results = struct( ...
        'cfg',         rmfield(cfg,intersect(fieldnames(cfg),{'MRSCont','progressFcn'})), ...
        'comp',        comp, ...
        'atlasMode',   atlas.mode, ...
        'nSubj',       nS, ...
        'roi',         roi, ...
        'centres',     locations, ...
        'densityPercentFile', fullfile(cfg.outDir,'voxel_density_percent_MNI.nii.gz'), ...
        'warpedPaths', {warpedPaths}, ...
        'densityFile', fullfile(cfg.outDir,'voxel_density_MNI.nii.gz'), ...
        'atlas',       struct('labelVol',atlas.labelVol,'values',atlas.values, ...
                              'name',atlas.name,'mode',atlas.mode));
    save(fullfile(cfg.outDir,'results.mat'), 'results');
    fprintf('[mva] done. Outputs written to %s\n', cfg.outDir);
end


% =========================================================================
function cfg = local_defaults(cfg)
    def = struct( ...
        'normMethod','unified', 'normTemplate','', ...
        'outVox',[1 1 1], 'outBB',[-78 -112 -70; 78 76 85], ...
        'atlasMode','maxprob', 'maskInterp',1, 'maskThresh',0.5, ...
        'otherThreshPct',2, 'topN',12, 'runSeg',false, ...
        'spmPath','', 'ospreyPath','', 'force',false, 'progressFcn',[]);
    fn = fieldnames(def);
    for i = 1:numel(fn)
        if ~isfield(cfg,fn{i}), cfg.(fn{i}) = def.(fn{i}); end
    end
    if isempty(cfg.maskThresh), cfg.maskThresh=0.5; end
    assert(isscalar(cfg.maskThresh) && cfg.maskThresh>0 && cfg.maskThresh<=1,'maskThresh must be in (0,1].');
    assert(isfield(cfg,'outDir')    && ~isempty(cfg.outDir),    'cfg.outDir is required.');
    assert(isfield(cfg,'atlasImage')&& ~isempty(cfg.atlasImage),'cfg.atlasImage is required.');
    if strcmpi(cfg.normMethod,'oldnorm') && isempty(cfg.normTemplate)
        fsldir = getenv('FSLDIR');
        if ~isempty(fsldir)
            cfg.normTemplate = fullfile(fsldir,'data','standard','MNI152_T1_1mm.nii.gz');
        else
            error('mva:tmpl','normMethod=''oldnorm'' needs cfg.normTemplate (or $FSLDIR set).');
        end
    end
end

% =========================================================================
function MRSCont = local_get_mrscont(cfg)
    if isfield(cfg,'MRSCont') && ~isempty(cfg.MRSCont)
        MRSCont = cfg.MRSCont;
    elseif isfield(cfg,'mrscontMat') && ~isempty(cfg.mrscontMat)
        S = load(cfg.mrscontMat);
        if isfield(S,'MRSCont'), MRSCont = S.MRSCont;
        else, f = fieldnames(S); MRSCont = S.(f{1}); end
    elseif isfield(cfg,'jobFile') && ~isempty(cfg.jobFile)
        MRSCont = OspreyJob(cfg.jobFile);
        % Existing jobs also run localisation without separate reference data.
        MRSCont.files_ref={}; MRSCont.files_w={};
        MRSCont.files_mm={}; MRSCont.files_mm_ref={};
        MRSCont.opts.ECC.raw=0; MRSCont.opts.ECC.mm=0;
        MRSCont = OspreyLoad(MRSCont);
        MRSCont = OspreyCoreg(MRSCont);
        if cfg.runSeg, MRSCont = OspreySeg(MRSCont); end
    else
        error('mva:noInput', ...
            'Provide cfg.MRSCont, cfg.mrscontMat, cfg.jobFile, or cfg.bidsDir.');
    end
    if ~isfield(MRSCont,'coreg') || ~isfield(MRSCont.coreg,'vol_mask') ...
            || isempty(MRSCont.coreg.vol_mask)
        % coregistration not done yet -> run it (and seg, for completeness)
        MRSCont = OspreyCoreg(MRSCont);
        if cfg.runSeg, MRSCont = OspreySeg(MRSCont); end
    end
end

% =========================================================================
function t1 = local_get_t1(MRSCont, kk)
% Resolve the structural T1 path for dataset kk. Tries the job's NIfTI list
% first, then the coreg structural volume handle.
    t1 = '';
    if isfield(MRSCont,'files_nii') && numel(MRSCont.files_nii) >= kk
        t1 = MRSCont.files_nii{kk};
        if iscell(t1), t1 = t1{1}; end
    end
    if (isempty(t1) || exist(char(t1),'file') ~= 2) ...
            && isfield(MRSCont.coreg,'vol_image') ...
            && numel(MRSCont.coreg.vol_image) >= kk
        vi = MRSCont.coreg.vol_image{kk};
        if iscell(vi), vi = vi{1}; end
        if isstruct(vi) && isfield(vi,'fname'), t1 = vi(1).fname; end
    end
    t1 = local_resolve_nii(char(t1));
    if isempty(t1) || exist(t1,'file') ~= 2
        error('mva:noT1','Could not locate the T1 for dataset %d.', kk);
    end
end

% =========================================================================
function m = local_get_mask(MRSCont, kk)
% Resolve the native-space voxel mask path for dataset kk.
    vm = MRSCont.coreg.vol_mask{kk};
    while iscell(vm)
        assert(numel(vm)==1,'Multiple voxels in one acquisition: select a single SVS voxel with Osprey first.');
        vm=vm{1};
    end
    if isstruct(vm), m = vm(1).fname; else, m = vm; end
    m = local_resolve_nii(char(m));
    if exist(m,'file') ~= 2
        error('mva:noMask','Voxel mask not found for dataset %d: %s', kk, m);
    end
end

% =========================================================================
function p = local_resolve_nii(p)
% Resolve Osprey handles without creating persistent uncompressed duplicates.
p=char(p);
if ~isfile(p) && isfile([p '.gz']), p=[p '.gz']; end
end
