function T = mva_scan_bids(root)
% Scan BIDS subjects/sessions. Never read vendor geometry or select a tie.
% Series formats (DICOM/IMA/RDA) are passed to Osprey as directories.
root = char(root);
assert(isfolder(root), 'Dataset folder not found: %s', root);
[~,base] = fileparts(root);
if startsWith(base,'sub-')
    subjects = dir(root); subjects = subjects([]);
    subjects(1).name = base; subjects(1).folder = fileparts(root);
else
    subjects = dir(fullfile(root,'sub-*')); subjects = subjects([subjects.isdir]);
end
rows = cell(0,12);
for s = 1:numel(subjects)
    sp = fullfile(subjects(s).folder, subjects(s).name);
    ses = dir(fullfile(sp,'ses-*')); ses = ses([ses.isdir]);
    if isempty(ses), paths = {sp}; names = {''};
    else, paths = arrayfun(@(x)fullfile(x.folder,x.name),ses,'UniformOutput',false); names = {ses.name}; end
    for j = 1:numel(paths)
        mp = fullfile(paths{j},'mrs');
        if ~isfolder(mp), continue; end
        d = dir(fullfile(mp,'**','*')); d = d(~[d.isdir]);
        scans = {}; rois = {}; refs = []; metas = {};
        for k = 1:numel(d)
            p = fullfile(d(k).folder,d(k).name);
            if endsWith(lower(p),'.nii.gz') && isfile(p(1:end-3)), continue; end
            if isempty(regexpi(p,'\.(dat|sdat|data|raw|7|p|nii|nii\.gz|dcm|ima|rda)$','once')), continue; end
            % RAW requires Philips SIN metadata; LCModel exports are not input.
            if endsWith(lower(p),'.raw') && isempty(dir(fullfile(d(k).folder,'*.sin'))) && isempty(dir(fullfile(d(k).folder,'*.SIN'))), continue; end
            if ~isempty(regexpi(p,'\.(dcm|ima|rda)$','once')), p = d(k).folder; end
            if any(strcmp(scans,p)), continue; end
            [roi,isref,meta] = identify(p,mp);
            scans{end+1,1} = p; rois{end+1,1} = roi; refs(end+1,1) = isref; metas{end+1,1} = meta; %#ok<AGROW>
        end
        td = dir(fullfile(paths{j},'anat','*T1w.nii*'));
        if isempty(td) && ~strcmp(paths{j},sp), td = dir(fullfile(sp,'anat','*T1w.nii*')); end
        t1s = arrayfun(@(x)fullfile(x.folder,x.name),td(~[td.isdir]),'UniformOutput',false);
        % A decompressed copy and its .gz are one image, not an ambiguity.
        for k = numel(t1s):-1:1
            if endsWith(t1s{k},'.gz') && any(strcmp(t1s,t1s{k}(1:end-3))), t1s(k)=[]; end
        end
        for k = find(~refs)'
            rp = ''; tp = ''; status = 'OK';
            if numel(t1s)==1, tp=t1s{1}; elseif isempty(t1s), status='Missing'; else, status='Choose file'; end
            note = 'Separate water references ignored: localisation only';
            if strcmp(rois{k},'Unassigned'), status='Choose file'; note='Set ROI name'; end
            if isfield(metas{k},'MixedSeries') && metas{k}.MixedSeries
                status='Choose file'; note='Mixed DICOM/IMA/RDA folder: separate acquisitions/references into series folders, then rescan';
            end
            rows(end+1,:)={true,subjects(s).name,names{j},rois{k},rois{k},scans{k},rp,tp,status,note,{},t1s}; %#ok<AGROW>
        end
    end
end
T=cell2table(rows(:,1:10),'VariableNames',{'Include','Subject','Session','Acquisition','ROI','MRS','Reference','T1','Status','Note'});
T.ReferenceCandidates=rows(:,11); T.T1Candidates=rows(:,12);
if isempty(T), return; end
T.Include=logical(T.Include);
keys=strcat(T.Subject,'|',T.ROI);
for k=1:height(T)
    if sum(strcmp(keys,keys{k}))>1
        T.Include(k)=false; T.Status{k}='Choose file';
        T.Note{k}='Repeated participant/ROI: select exactly one acquisition, or assign distinct ROI names';
    end
end
end

function [roi,isref,md] = identify(p,mrsroot)
rel = strrep(p,[mrsroot filesep],'');
[~,name] = fileparts(regexprep(p,'\.nii\.gz$','.nii','ignorecase'));
md=struct(); side=regexprep(p,'\.[^.]+$','.json');
if endsWith(lower(p),'.nii.gz'), side=[p(1:end-7) '.json']; end
if isfile(side)
    try, md=jsondecode(fileread(side)); catch ME, warning('mva:metadata','Cannot read %s: %s',side,ME.message); end
end
isref=~isempty(regexpi(rel,'(^|[_/\\-])(wref|ref|water|reference)([_/\\.-]|$)','once'));
if isfield(md,'WaterSuppressed') && isequal(md.WaterSuppressed,false), isref=true; end
roi='';
for f={'VOI','VoxelName','AnatomicalRegion','RegionOfInterest'}
    if isfield(md,f{1}) && (ischar(md.(f{1})) || isstring(md.(f{1}))), roi=char(md.(f{1})); break; end
end
if isempty(roi)
    tok=regexp(rel,'acq-([A-Za-z0-9]+)','tokens','once');
    if ~isempty(tok), roi=tok{1}; end
end
if isempty(roi)
    tok=regexpi(rel,'(^|[_/\\-])(PCC|ACC|DLPFC|ACG|PCG|svs\d+)(?=[_/\\.-]|$)','tokens','once');
    if ~isempty(tok), roi=tok{2}; end
end
if isempty(roi)
    name=regexprep(name,'([_-])(wref|ref|water|reference)$','','ignorecase');
    if ~isempty(name) && ~startsWith(name,'sub-') && isempty(regexpi(name,'^meas_|^IM|^MR','once')), roi=name; end
end
if isempty(roi) || ismember(lower(roi),{'mrs','spectroscopy'}), roi='Unassigned'; end
if isfolder(p)
    ff=dir(fullfile(p,'*')); ff=ff(~[ff.isdir]);
    keys={};
    for j=1:numel(ff)
        if isempty(regexpi(ff(j).name,'\.(dcm|ima|rda)$','once')), continue; end
        [rr,ww]=identify(fullfile(p,ff(j).name),mrsroot);
        keys{end+1}=sprintf('%s|%d',rr,ww); %#ok<AGROW>
    end
    md.MixedSeries=numel(unique(keys))>1;
end
end
