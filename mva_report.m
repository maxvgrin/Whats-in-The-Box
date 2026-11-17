function mva_report(comp, density, refMat, refDim, cfg)
%MVA_REPORT  Write tables, the density NIfTI, and figures.  ("Output").
%
%   mva_report(comp, density, refMat, refDim, cfg)
%
% Produces in cfg.outDir:
%   voxel_density_MNI.nii.gz                  - summed across-subject density map
%   composition_density_weighted.csv       - region, value, density-weighted %
%   composition_per_subject_summary.csv     - region, mean %, SD %, N
%   composition_per_subject_matrix.csv      - full [subject x region] matrix
%   pie_density_weighted.png                - headless only (saveCharts=true)
%   bar_mean_per_subject.png                - headless only (saveCharts=true)
%
% Part of the MRS Voxel Atlas Composition toolbox.
% -------------------------------------------------------------------------

    od = cfg.outDir;
    if ~exist(od,'dir'), mkdir(od); end

    % ---- 1. density NIfTI ----------------------------------------------
    densHdr = struct( ...
        'fname',   fullfile(od,'voxel_density_MNI.nii'), ...
        'dim',     double(refDim(:)'), ...
        'dt',      [spm_type('float32') 0], ...
        'mat',     refMat, ...
        'pinfo',   [1;0;0], ...
        'n',       [1 1], ...
        'descrip', 'MRS voxel density (sum of warped masks)');
    spm_write_vol(densHdr, density);
    mva_compress_nifti(densHdr.fname);
    densHdr.fname=fullfile(od,'voxel_density_percent_MNI.nii');
    densHdr.descrip=sprintf('Percent of %d successfully processed participants',comp.nSubj);
    spm_write_vol(densHdr,100*density/comp.nSubj);
    mva_compress_nifti(densHdr.fname);

    % ---- 2. CSV tables -------------------------------------------------
    ord = comp.order;

    Tdens = table(comp.region(ord), comp.value(ord), comp.densityPct(ord), ...
        'VariableNames', {'Region','Value','DensityWeightedPct'});
    Tdens = [Tdens; ...
        cell2table({'Unlabeled_or_outside_atlas', NaN, comp.unlabeledDensityPct}, ...
        'VariableNames', Tdens.Properties.VariableNames)];
    writetable(Tdens, fullfile(od,'composition_density_weighted.csv'));

    Tsum = table(comp.region(ord), comp.meanPct(ord), comp.sdPct(ord), ...
        repmat(comp.nSubj,numel(ord),1), ...
        'VariableNames', {'Region','MeanPct','SDPct','N'});
    writetable(Tsum, fullfile(od,'composition_per_subject_summary.csv'));

    Mt = array2table(comp.subjPct, ...
        'VariableNames', matlab.lang.makeUniqueStrings(matlab.lang.makeValidName(comp.region)));
    subjectIDs = (1:comp.nSubj)';
    if isfield(cfg,'subjectIDs'), subjectIDs=cfg.subjectIDs; end
    Mt = addvars(Mt, subjectIDs, 'Before', 1, 'NewVariableNames', 'Subject');
    writetable(Mt, fullfile(od,'composition_per_subject_matrix.csv'));

    % GUI charts are exported only by the explicit Save buttons.
    if isfield(cfg,'saveCharts') && ~cfg.saveCharts, return; end

    % ---- 3. pie (density-weighted, small slices grouped as "Other") ----
    pct = comp.densityPct(ord);
    nm  = comp.region(ord);
    big = pct >= cfg.otherThreshPct;
    pieVals  = [pct(big); sum(pct(~big)) + comp.unlabeledDensityPct];
    pieNames = [nm(big);  {'Other / unlabeled'}];
    pieVals  = max(pieVals, eps);   % guard against zero slices

    f1 = figure('Color','w','Position',[100 100 900 560],'Visible','off');
    hpie = pie(pieVals, repmat({''}, numel(pieVals), 1));  % no on-slice labels: thin slices collide
    delete(findobj(hpie,'Type','text'));                   % drop any stray % text
    legNames = arrayfun(@(i) sprintf('%s  (%.1f%%)', pieNames{i}, pieVals(i)), ...
                        (1:numel(pieVals))', 'UniformOutput', false);
    legend(legNames,'Location','eastoutside','Interpreter','none','Box','off');

    local_savefig(f1, fullfile(od,'pie_density_weighted.png'));
    close(f1);

    % ---- 4. bar (per-subject mean +/- SD, top N) -----------------------
    n   = min(cfg.topN, numel(ord));
    idx = ord(1:n);
    f2 = figure('Color','w','Position',[100 100 920 520],'Visible','off');
    bar(comp.meanPct(idx)); hold on;
    errorbar(1:n, comp.meanPct(idx), comp.sdPct(idx), 'k', ...
             'LineStyle','none','CapSize',4);
    set(gca,'XTick',1:n,'XTickLabel',comp.region(idx), ...
            'TickLabelInterpreter','none');
    xtickangle(40);
    ylabel('% of voxel  (per-subject mean \pm SD)');

    box off;
    local_savefig(f2, fullfile(od,'bar_mean_per_subject.png'));
    close(f2);
end

% =========================================================================
function local_savefig(f, fname)
    try
        exportgraphics(f, fname, 'Resolution', 200);
    catch
        print(f, fname, '-dpng', '-r200');
    end
end
