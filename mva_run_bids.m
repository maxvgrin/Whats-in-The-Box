function batch = mva_run_bids(cfg)
% Selected acquisitions run independently; cohort denominator is participants.
addpath(fileparts(mfilename('fullpath')));
cfg.outDir=local_absolute(cfg.outDir);
for field={'spmPath','ospreyPath'}
    if isfield(cfg,field{1}) && ~isempty(cfg.(field{1})), cfg.(field{1})=local_absolute(cfg.(field{1})); end
end
if isfield(cfg,'spmPath') && ~isempty(cfg.spmPath), addpath(cfg.spmPath); end
if isfield(cfg,'ospreyPath') && ~isempty(cfg.ospreyPath), addpath(genpath(cfg.ospreyPath)); end
assert(exist('spm','file')==2 && exist('OspreyJob','file')==2, 'Add SPM and Osprey in Advanced settings.');
if isfield(cfg,'assignments'), T=cfg.assignments; else, T=mva_scan_bids(cfg.bidsDir); end
for k=1:height(T)
    T.MRS{k}=local_absolute(T.MRS{k}); T.T1{k}=local_absolute(T.T1{k});
end
T=mva_validate_assignments(T);
assert(any(T.Include),'Select at least one acquisition.');
assert(all(strcmp(T.Status(T.Include),'OK')),'Resolve selected assignments before running.');
if ~isfolder(cfg.outDir), mkdir(cfg.outDir); end
writetable(T(:,1:10),fullfile(cfg.outDir,'subject_file_assignments.csv'));
map=unique(T(:,{'Acquisition','ROI'}),'rows'); writetable(map,fullfile(cfg.outDir,'roi_mapping.csv'));
T=T(T.Include,:); rois=unique(T.ROI,'stable'); batch=struct('rois',{rois},'results',{{}});
[useParallel,workerCount]=mva_parallel_setup(cfg);
for r=1:numel(rois)
    Q=T(strcmp(T.ROI,rois{r}),:); od=fullfile(cfg.outDir,rois{r});
    if ~isfolder(od), mkdir(od); end
    mva_write_osprey_job(Q,od,cfg); % One reviewable cohort job plus isolated jobs below.
    C=struct(); C.coreg.vol_mask={}; C.files_nii={}; good=[];
    containers=cell(height(Q),1); errors=cell(height(Q),1);
    workerCfg=cfg;
    for field={'progressFcn','assignments'}
        if isfield(workerCfg,field{1}), workerCfg=rmfield(workerCfg,field{1}); end
    end
    if useParallel
        % No GUI handles or shared containers enter the workers.
        rows=cell(height(Q),1);
        for k=1:height(Q), rows{k}=Q(k,:); end
        parfor (k=1:height(Q), workerCount)
            [containers{k},errors{k}]=mva_coreg_acquisition(rows{k},od,workerCfg);
        end
    else
        for k=1:height(Q)
            [containers{k},errors{k}]=mva_coreg_acquisition(Q(k,:),od,workerCfg);
            if isfield(cfg,'progressFcn') && ~isempty(cfg.progressFcn), cfg.progressFcn(k,height(Q)); end
        end
    end
    for k=1:height(Q)
        if isempty(errors{k}) && ~isempty(containers{k})
            MRSCont=containers{k};
            C.coreg.vol_mask{end+1}=MRSCont.coreg.vol_mask{1};
            if isfield(MRSCont,'files_nii'), C.files_nii{end+1}=MRSCont.files_nii{1}; else, C.files_nii{end+1}=Q.T1{k}; end
            good(end+1)=k; Q.Note{k}='Osprey coregistration complete'; %#ok<AGROW>
        else
            Q.Status{k}='Failed'; Q.Note{k}=errors{k};
            warning('mva:subjectFailed','%s / %s: %s',rois{r},Q.Subject{k},errors{k});
        end
    end
    if useParallel && isfield(cfg,'progressFcn') && ~isempty(cfg.progressFcn), cfg.progressFcn(height(Q),height(Q)); end
    writetable(Q(:,1:10),fullfile(od,'subject_file_assignments.csv'));
    if isempty(good), batch.results{r}=[]; continue; end
    rcfg=cfg;
    for f={'bidsDir','assignments','jobFile','mrscontMat'}
        if isfield(rcfg,f{1}), rcfg=rmfield(rcfg,f{1}); end
    end
    rcfg.MRSCont=C; rcfg.outDir=od; rcfg.subjectIDs=Q.Subject(good); rcfg.roi=rois{r}; rcfg.runSeg=false;
    rcfg.maskThresh=0.5; % Count participants, not fractional mask weights.
    try
        batch.results{r}=run_mrs_atlas_composition(rcfg);
        done=batch.results{r}.centres.Subject;
        for k=good
            if ismember(Q.Subject{k},done), Q.Note{k}='Complete';
            else, Q.Status{k}='Failed'; Q.Note{k}='Normalisation failed; see failed_subjects.csv'; end
        end
    catch ME
        batch.results{r}=[];
        warning('mva:roiFailed','ROI %s failed: %s',rois{r},ME.message);
        Q.Status(good)={'Failed'}; Q.Note(good)={ME.message};
    end
    writetable(Q(:,1:10),fullfile(od,'subject_file_assignments.csv'));
end
ok=~cellfun(@isempty,batch.results); batch.rois=batch.rois(ok); batch.results=batch.results(ok);
assert(~isempty(batch.results),'No ROI completed. See assignment tables for subject errors.');
save(fullfile(cfg.outDir,'cohort_results.mat'),'batch','-v7.3');
end

function p=local_absolute(p)
p=char(p);
if isempty(p), return; end
if isempty(regexp(p,'^([A-Za-z]:[\\/]|/|\\\\)','once')), p=fullfile(pwd,p); end
end
