
clear cfg

% --- Osprey results: choose ONE ------------------------------------------
% (A) an Osprey job listing every subject's T1 (files_nii) + MRS data:
 cfg.jobFile    = '/path/to/jobCohort.m';
%
% (B) a previously-saved MRSCont with coregistration already done:
#cfg.mrscontMat   = '/path/to/derivatives/osprey/MRSCont.mat';
%
% (C) an in-memory container:
% cfg.MRSCont    = MRSCont;

% --- Atlas (FSL example: Harvard-Oxford subcortical, 1 mm) ---------------
fsldir = getenv('FSLDIR');           % e.g. '/usr/local/fsl'
cfg.atlasImage = fullfile(fsldir,'data','atlases','HarvardOxford', ...
                          'HarvardOxford-sub-maxprob-thr25-1mm.nii.gz');
cfg.atlasXML   = fullfile(fsldir,'data','atlases', ...
                          'HarvardOxford-Subcortical.xml');
cfg.atlasMode  = 'maxprob';          % hard labels (default)

% For a non-FSL atlas (e.g. AAL), drop atlasXML and use a CSV LUT instead:
% cfg.atlasImage = '/path/to/AAL.nii';
% cfg.atlasLUT   = '/path/to/AAL_lut.csv';   % columns: value,name

% --- Toolboxes & output --------------------------------------------------
cfg.spmPath    = '/path/to/spm12';
cfg.ospreyPath = '/path/to/osprey';
cfg.outDir     = fullfile(pwd,'mrs_atlas_out');

% --- Options (optional) --------------------------------------------------
cfg.outVox         = [1 1 1];        % match the atlas resolution
cfg.otherThreshPct = 2;              % group <2% slices into "Other" in the pie
cfg.topN           = 12;             % regions shown in the bar chart

% For EXACT FSL-MNI alignment (instead of SPM-MNI) use Old Normalise to the
% FSL template your atlas is registered to:
% cfg.normMethod   = 'oldnorm';
% cfg.normTemplate = fullfile(fsldir,'data','standard','MNI152_T1_1mm.nii.gz');

% --- Run -----------------------------------------------------------------
results = run_mrs_atlas_composition(cfg);

% --- Quick look ----------------------------------------------------------
fprintf('\nTop regions (density-weighted):\n');
ord = results.comp.order;
for r = 1:min(10, numel(ord))
    fprintf('  %-34s %5.1f %%\n', results.comp.region{ord(r)}, ...
            results.comp.densityPct(ord(r)));
end
fprintf('  %-34s %5.1f %%\n', 'Unlabeled / outside atlas', ...
        results.comp.unlabeledDensityPct);
