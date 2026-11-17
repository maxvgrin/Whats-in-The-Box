function [MRSCont, message] = mva_coreg_acquisition(Q, od, cfg)
% One isolated acquisition, used by both for and parfor. Osprey is unchanged.
MRSCont=[]; message=''; force=isfield(cfg,'force') && cfg.force;
try
    if isfield(cfg,'spmPath') && ~isempty(cfg.spmPath), addpath(cfg.spmPath); end
    if isfield(cfg,'ospreyPath') && ~isempty(cfg.ospreyPath), addpath(genpath(cfg.ospreyPath)); end
        sd=fullfile(od,Q.Subject{1}); if ~isfolder(sd), mkdir(sd); end
        previous=pwd; restore=onCleanup(@()cd(previous)); cd(sd);
        job=mva_write_osprey_job(Q,sd,cfg);
        % Fingerprint inputs and job options; never reuse a different assignment.
        sig=struct('job',fileread(job),'inputs',{{}});
        for p=[Q.MRS;Q.T1]'
            if isempty(p{1}), continue; end
            d=dir(p{1}); if isfolder(p{1}), d=dir(fullfile(p{1},'**','*')); end
            sig.inputs{end+1}=d;
        end
        cache=fullfile(sd,'coreg_cache.mat');
            cached=false;
            if isfile(cache) && ~force
                old=load(cache,'signature','MRSCont');
                cached=isfield(old,'signature') && isequaln(old.signature,sig);
                if cached
                    MRSCont=old.MRSCont; vm=MRSCont.coreg.vol_mask{1};
                    while iscell(vm), vm=vm{1}; end
                    if isstruct(vm), vm=vm.fname; end
                    cached=isfile(vm) || isfile([vm '.gz']);
                    if cached
                        t1=MRSCont.files_nii{1}; while iscell(t1), t1=t1{1}; end
                        cached=isfile(t1) || isfile([t1 '.gz']);
                    end
                end
            end
            if ~cached
                % Stage anatomy: Osprey may write alongside it; never share it across workers.
                anatomyDir=fullfile(sd,'anatomy'); if ~isfolder(anatomyDir), mkdir(anatomyDir); end
                [~,an,ae]=fileparts(Q.T1{1}); staged=fullfile(anatomyDir,[an ae]);
                if endsWith(lower(staged),'.gz') && isfile(staged(1:end-3)), delete(staged(1:end-3)); end
                copyfile(Q.T1{1},staged,'f');
                workerQ=Q; workerQ.T1={staged};
                job=mva_write_osprey_job(workerQ,sd,cfg);
                MRSCont=OspreyJob(job,0,'11'); MRSCont=OspreyLoad(MRSCont); MRSCont=OspreyCoreg(MRSCont);
                % Cache only localisation handles, not another copy of raw spectra.
                coreg=struct('vol_mask',{MRSCont.coreg.vol_mask});
                MRSCont=struct('coreg',coreg,'files_nii',{MRSCont.files_nii});

            end
            assert(numel(MRSCont.coreg.vol_mask)==1,'Expected one SVS voxel per selected acquisition.');

    % Compact only owned Osprey masks/anatomy, never external input files.
    vm=MRSCont.coreg.vol_mask{1}; while iscell(vm), vm=vm{1}; end
    if isstruct(vm), vm=vm.fname; end
    vm=local_compact_owned(vm,sd);
    MRSCont.coreg.vol_mask{1}=vm;
    t1=MRSCont.files_nii{1}; while iscell(t1), t1=t1{1}; end
    MRSCont.files_nii{1}=local_compact_owned(t1,sd);
    signature=sig; save(cache,'MRSCont','signature','-v7.3');

catch ME
    MRSCont=[]; message=ME.message;
end
end

function p=local_compact_owned(p,sd)
p=char(p);
if ~isfile(p) && isfile([p '.gz']), p=[p '.gz']; end
% Only these directories are exclusively owned by this acquisition.
owned=startsWith(p,[fullfile(sd,'osprey') filesep]) || startsWith(p,[fullfile(sd,'anatomy') filesep]);
if ~owned, return; end
if endsWith(lower(p),'.nii') && isfile(p)
    p=mva_compress_nifti(p);
elseif endsWith(lower(p),'.nii.gz') && isfile(p(1:end-3))
    % The live NIfTI is authoritative after an Osprey run.
    p=mva_compress_nifti(p(1:end-3));
end
end
