function wmask = mva_warp_voxel_to_mni(T1path, maskPath, cfg)
% wmask = mva_warp_voxel_to_mni(T1path, maskPath, cfg)
%
% Two normalisation backends (cfg.normMethod):
%   'unified' (default) - SPM12 "Normalise: Estimate" (unified segmentation).
%                         Produces/uses a forward deformation y_<T1>.nii and
%                         applies it to the mask. Target = SPM/ICBM MNI.
%   'oldnorm'           - SPM12 "Old Normalise (Est & Wri)" to cfg.normTemplate
%                         (point it at the FSL MNI152 template your atlas lives
%                         in -> masks land EXACTLY in the atlas space).


    T1path   = char(T1path);
    maskPath = char(maskPath);
    if isfield(cfg,'mniMaskPath')
        wmask=cfg.mniMaskPath;
    else
        [mp,mn]=fileparts(regexprep(maskPath,'\.gz$',''));
        wmask=fullfile(mp,['w' mn '.nii.gz']);
    end
    cacheFile=[wmask '.mat'];
    templateInfo=[]; if ~isempty(cfg.normTemplate), templateInfo=dir(cfg.normTemplate); end
    signature=struct('T1',T1path,'mask',dir(maskPath),'t1info',dir(T1path), ...
        'method',cfg.normMethod,'vox',cfg.outVox,'bb',cfg.outBB,'interp',cfg.maskInterp, ...
        'template',cfg.normTemplate,'templateInfo',templateInfo);
    if isfile(wmask) && isfile(cacheFile) && ~cfg.force
        old=load(cacheFile,'signature');
        if isfield(old,'signature') && isequaln(old.signature,signature), return; end
    end

    % SPM writes beside its inputs. Keep anatomy/deformation in an owned cache
    % and the native/warped mask in a disposable workspace, never source data.
    normDir=fullfile(fileparts(wmask),'normalisation');
    if ~isfolder(normDir), mkdir(normDir); end
    sourceCache=fullfile(normDir,'t1_source.mat');
    t1signature=struct('path',T1path,'info',dir(T1path));
    anatomy=fullfile(normDir,'T1.nii'); reuse=false;
    if isfile(sourceCache) && (isfile(anatomy) || isfile([anatomy '.gz'])) && ~cfg.force
        old=load(sourceCache,'t1signature');
        reuse=isfield(old,'t1signature') && isequaln(old.t1signature,t1signature);
    end
    if ~reuse
        [t1plain,t1cleanup]=mva_temp_nii(T1path);
        copyfile(t1plain,anatomy,'f'); clear t1cleanup;
        if isfile([anatomy '.gz']), delete([anatomy '.gz']); end
        % Invalidate the deformation if the anatomical source changed.
        y=fullfile(normDir,'y_T1.nii');
        if isfile(y), delete(y); end
        if isfile([y '.gz']), delete([y '.gz']); end
        save(sourceCache,'t1signature');
    elseif ~isfile(anatomy)
        gunzip([anatomy '.gz'],normDir);
    end
    T1path=anatomy;
    anatomyCleanup=onCleanup(@()local_pack_anatomy(normDir)); %#ok<NASGU>
    y=fullfile(normDir,'y_T1.nii');
    if ~isfile(y) && isfile([y '.gz']), gunzip([y '.gz'],normDir); end
    workDir=tempname; mkdir(workDir);
    workCleanup=onCleanup(@()rmdir(workDir,'s')); %#ok<NASGU>
    [plain,maskCleanup]=mva_temp_nii(maskPath);
    maskPath=fullfile(workDir,'voxel_native.nii'); copyfile(plain,maskPath);
    clear maskCleanup;
    generated=fullfile(workDir,'wvoxel_native.nii');
    templateCleanup=[]; %#ok<NASGU>
    if strcmpi(cfg.normMethod,'oldnorm')
        [cfg.normTemplate,templateCleanup]=mva_temp_nii(cfg.normTemplate);
    end

    switch lower(cfg.normMethod)

        % =================================================================
        case 'unified'
            % --- ensure forward deformation y_<T1>.nii exists ------------
            [tp, tn] = fileparts(T1path);
            yfile = fullfile(tp, ['y_' tn '.nii']);

            yd=dir(yfile); td=dir(T1path);
            if isempty(yd) || yd.datenum<td.datenum || cfg.force
                tpm = fullfile(fileparts(which('spm')), 'tpm', 'TPM.nii');
                clear matlabbatch
                e = struct();
                e.subj.vol            = {[T1path ',1']};
                e.eoptions.biasreg    = 1e-4;
                e.eoptions.biasfwhm   = 60;
                e.eoptions.tpm        = {tpm};
                e.eoptions.affreg     = 'mni';
                e.eoptions.reg        = [0 1e-3 0.5 0.05 0.2];
                e.eoptions.fwhm       = 0;
                e.eoptions.samp       = 3;
                matlabbatch{1}.spm.spatial.normalise.est = e;
                spm_jobman('run', matlabbatch);
            end

            % --- apply the deformation to the mask ----------------------
            clear matlabbatch
            w = struct();
            w.subj.def          = {yfile};
            w.subj.resample     = {[maskPath ',1']};
            w.woptions.bb       = cfg.outBB;
            w.woptions.vox      = cfg.outVox;
            w.woptions.interp   = cfg.maskInterp;   % 1 = trilinear -> PV mask
            w.woptions.prefix   = 'w';
            matlabbatch{1}.spm.spatial.normalise.write = w;
            spm_jobman('run', matlabbatch);

        % =================================================================
        case 'oldnorm'
            % Old Normalise estimates the T1->template warp and applies it
            % to the mask (which is in T1 space). Use cfg.normTemplate =
            % the FSL MNI152 template your atlas is registered to.
            clear matlabbatch
            o = struct();
            o.subj.source        = {[T1path ',1']};
            o.subj.wtsrc         = '';
            o.subj.resample      = {[maskPath ',1']};
            o.eoptions.template  = {[char(cfg.normTemplate) ',1']};
            o.eoptions.weight    = '';
            o.eoptions.smosrc    = 8;
            o.eoptions.smoref    = 0;
            o.eoptions.regtype   = 'mni';
            o.eoptions.cutoff    = 25;
            o.eoptions.nits      = 16;
            o.eoptions.reg       = 1;
            o.roptions.preserve  = 0;
            o.roptions.bb        = cfg.outBB;
            o.roptions.vox       = cfg.outVox;
            o.roptions.interp    = cfg.maskInterp;
            o.roptions.prefix    = 'w';
            matlabbatch{1}.spm.tools.oldnorm.estwrite = o;
            spm_jobman('run', matlabbatch);

        otherwise
            error('mva:normMethod','Unknown cfg.normMethod: %s', cfg.normMethod);
    end

    if exist(generated,'file') ~= 2
        error('mva:warpFailed','Warped mask was not produced: %s', wmask);
    end
    gz=mva_compress_nifti(generated);
    movefile(gz,wmask,'f');
    save(cacheFile,'signature');
end

function local_pack_anatomy(d)
% These are owned reusable SPM cache files, not source images.
for name={'T1.nii','y_T1.nii'}
    p=fullfile(d,name{1});
    if isfile(p)
        try, mva_compress_nifti(p);
        catch ME, warning('mva:cacheCompression','%s',ME.message); end
    end
end
end
