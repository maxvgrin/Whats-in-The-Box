function atlas = mva_load_atlas(cfg, refMat, refDim)
%MVA_LOAD_ATLAS  Load an atlas, build a value->name lookup, align to a grid.
%
%   atlas = mva_load_atlas(cfg, refMat, refDim)
%
% Workflow step 5 ("Overlay with Atlas"). The atlas is read (handling
% .nii.gz), labelled by name, and resampled onto the reference grid (the MNI
% grid of the warped voxel masks) so that overlap can be computed voxelwise.
%
% Lookup source (one required):
%   cfg.atlasXML - FSL atlas .xml (e.g. HarvardOxford-Subcortical.xml)
%   cfg.atlasLUT - CSV with columns value,name  (for AAL or any other atlas;
%                  'value' is the literal intensity in the label image)
%
% OUTPUT struct atlas:
%   atlas.mode     - 'maxprob' or 'prob'
%   atlas.labelVol - integer label volume on the reference grid (NN)
%   atlas.values   - row vector of label values present (>0)
%   atlas.name     - containers.Map: value -> region name
%   atlas.probVol  - (prob mode only) 4D probabilities on the grid, in [0 1]
%
% IMPORTANT (FSL convention): for maxprob/summary images the voxel value is
% the XML index + 1 (0 = background). This function keys names by image value
% accordingly, so it is correct for both maxprob and prob atlases.
% -------------------------------------------------------------------------

    % --- value -> name lookup -------------------------------------------
    if isfield(cfg,'atlasSource') && strcmpi(cfg.atlasSource,'CAT12')
        nameMap=mva_read_cat_labels(cfg.atlasLUT);
    elseif isfield(cfg,'atlasXML') && ~isempty(cfg.atlasXML)
        nameMap = local_parse_fsl_xml(cfg.atlasXML);
    elseif isfield(cfg,'atlasLUT') && ~isempty(cfg.atlasLUT)
        nameMap = local_parse_lut_csv(cfg.atlasLUT);
    else
        error('mva:atlasLUT','Provide cfg.atlasXML or cfg.atlasLUT.');
    end

    % --- read the atlas image (handles .nii.gz) -------------------------
    A = mva_read_vol(cfg.atlasImage);

    atlas      = struct();
    atlas.mode = lower(cfg.atlasMode);
    atlas.name = nameMap;

    switch atlas.mode
        case 'maxprob'
            lab = mva_resample_to_ref(A.img(:,:,:,1), A.mat, refMat, refDim, 0);
            atlas.labelVol = round(lab);
            atlas.values   = unique(atlas.labelVol(atlas.labelVol>0))';

        case 'prob'
            nV = size(A.img,4);
            P  = zeros([refDim nV]);
            for v = 1:nV
                P(:,:,:,v) = mva_resample_to_ref(A.img(:,:,:,v), A.mat, ...
                                                 refMat, refDim, 1);
            end
            atlas.probVol = P / 100;                 % FSL prob is 0..100
            [pmax, amax]  = max(atlas.probVol, [], 4);
            lab = amax; lab(pmax <= 0) = 0;          % volume index = value
            atlas.labelVol = lab;
            atlas.values   = 1:nV; % Retain regions that never win the argmax.

        otherwise
            error('mva:atlasMode','cfg.atlasMode must be ''maxprob'' or ''prob''.');
    end

    % --- clean up temporary gunzipped atlas -----------------------------
    if A.gz
        try, rmdir(fileparts(A.fname),'s'); catch, end
    end
end

% =========================================================================
function nameMap = local_parse_fsl_xml(xmlPath)
% Parse an FSL atlas XML. Keys the map by IMAGE VALUE (= XML index + 1),
% matching the summary/maxprob image convention.
    dom    = xmlread(char(xmlPath));
    labels = dom.getElementsByTagName('label');
    nameMap = containers.Map('KeyType','double','ValueType','char');
    for i = 0:labels.getLength-1
        node = labels.item(i);
        idx  = str2double(char(node.getAttribute('index')));   % 0-based
        nm   = strtrim(char(node.getTextContent()));
        if ~isnan(idx)
            nameMap(idx+1) = nm;        % image value = index + 1
        end
    end
end

% =========================================================================
function nameMap = local_parse_lut_csv(csvPath)
% Parse a generic lookup table CSV with columns value,name. Keys the map by
% the literal label-image intensity (no off-by-one).
    T  = readtable(char(csvPath));
    vn = lower(string(T.Properties.VariableNames));
    vi = find(vn=="value",1);  if isempty(vi), vi = 1; end
    ni = find(vn=="name",1);   if isempty(ni), ni = 2; end
    vals = double(T{:,vi});
    nms  = string(T{:,ni});
    nameMap = containers.Map('KeyType','double','ValueType','char');
    for i = 1:numel(vals)
        nameMap(vals(i)) = char(nms(i));
    end
end
