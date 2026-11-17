function comp = mva_compute_composition(density, warpedMasks, atlas, cfg)
% Workflow step 6 ("Calculate Composition"). Computes two complementary
% quantities (see README for when to use which):
%
%   (a) Density-weighted composition  - the % of the summed across-subject
%       voxel density that falls in each atlas region. This is exactly the
%       pie chart in the reference figure.
%
%   (b) Per-subject composition       - the % of each individual voxel in
%       each region, then summarised as mean +/- SD across subjects.
%
% INPUT
%   density     - 3D summed density map (sum of warped masks), on the grid
%   warpedMasks - cell array {nSubj} of per-subject 3D warped masks (same grid)
%   atlas       - struct from mva_load_atlas (labelVol/values/name[/probVol])
%
% OUTPUT struct comp:
%   comp.region              - {nR} region names
%   comp.value               - [nR] label values
%   comp.densityPct          - [nR] density-weighted % (a)
%   comp.subjPct             - [nSubj x nR] per-subject % (b)
%   comp.meanPct, comp.sdPct - [nR] mean / SD across subjects
%   comp.unlabeledDensityPct - % of density outside atlas labels
%   comp.unlabeledMeanPct    - mean per-subject % outside atlas labels
%   comp.order               - region order sorted by densityPct (descending)
%   comp.nSubj               - number of subjects

    A    = atlas.labelVol;
    vals = atlas.values(:)';
    nR   = numel(vals);
    isProb = strcmp(atlas.mode,'prob');

    % ---- (a) density-weighted composition ------------------------------
    totalD  = sum(density(:));
    if totalD <= 0
        error('mva:emptyDensity','Density map is empty (no overlap found).');
    end
    densPct = zeros(1,nR);
    if isProb
        for r = 1:nR
            P = atlas.probVol(:,:,:,vals(r));
            densPct(r) = 100 * sum(density(:).*P(:)) / totalD;
        end
        anyP = sum(atlas.probVol,4);
        unlabD = 100 * sum(density(anyP<=0)) / totalD;
    else
        for r = 1:nR
            densPct(r) = 100 * sum(density(A==vals(r))) / totalD;
        end
        unlabD = 100 * sum(density(A==0)) / totalD;
    end

    % ---- (b) per-subject composition -----------------------------------
    nS      = numel(warpedMasks);
    subjPct = zeros(nS,nR);
    unlabS  = zeros(nS,1);
    for s = 1:nS
        W   = warpedMasks{s};
        tot = sum(W(:));
        if tot <= 0, continue; end
        if isProb
            for r = 1:nR
                P = atlas.probVol(:,:,:,vals(r));
                subjPct(s,r) = 100 * sum(W(:).*P(:)) / tot;
            end
            anyP = sum(atlas.probVol,4);
            unlabS(s) = 100 * sum(W(anyP<=0)) / tot;
        else
            for r = 1:nR
                subjPct(s,r) = 100 * sum(W(A==vals(r))) / tot;
            end
            unlabS(s) = 100 * sum(W(A==0)) / tot;
        end
    end

    % ---- names ---------------------------------------------------------
    names = cell(1,nR);
    for r = 1:nR
        if isKey(atlas.name, vals(r))
            names{r} = atlas.name(vals(r));
        else
            names{r} = sprintf('Label_%d', vals(r));
        end
    end

    % ---- assemble ------------------------------------------------------
    comp.region              = names(:);
    comp.value               = vals(:);
    comp.densityPct          = densPct(:);
    comp.subjPct             = subjPct;
    comp.meanPct             = mean(subjPct,1)';
    comp.sdPct               = std(subjPct,0,1)';
    comp.unlabeledDensityPct = unlabD;
    comp.unlabeledMeanPct    = mean(unlabS);
    comp.nSubj               = nS;

    [~, comp.order] = sort(comp.densityPct,'descend');
end
