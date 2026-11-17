function P=mva_discover_atlases(spmPath)
if nargin<1 || isempty(spmPath), spmPath=fileparts(which('spm')); end
P=struct('name',{},'img',{},'lut',{},'lutType',{},'mode',{},'source',{});
roots={};
if ~isempty(spmPath), roots{end+1}=fullfile(spmPath,'toolbox','cat12'); end
cp=which('cat12'); if ~isempty(cp), roots{end+1}=fileparts(cp); end
for root=unique(roots)
    if ~isfolder(root{1}), continue; end
    files=[dir(fullfile(root{1},'**','*.nii'));dir(fullfile(root{1},'**','*.nii.gz'))];
    for k=1:numel(files)
        img=fullfile(files(k).folder,files(k).name);
        stem=regexprep(img,'\.nii(\.gz)?$',''); lut=''; typ='';
        for ext={'.csv','.xml','.txt'}
            if isfile([stem ext{1}]), lut=[stem ext{1}]; typ='cat'; break; end
        end
        if isempty(lut), continue; end
        [~,nm]=fileparts(stem); [~,space]=fileparts(files(k).folder);
        P(end+1)=entry(['CAT12: ' nm ' (' space ')'],img,lut,typ,'CAT12'); %#ok<AGROW>
    end
end
% FSL atlases can live in resources/fsl/atlases without an FSL installation.
roots={fullfile(fileparts(mfilename('fullpath')),'resources','fsl','atlases')};
fsl=getenv('FSLDIR'); if ~isempty(fsl), roots{end+1}=fullfile(fsl,'data','atlases'); end
for root=roots
    x=dir(fullfile(root{1},'*.xml'));
    for k=1:numel(x)
        lut=fullfile(x(k).folder,x(k).name);
        try
            dom=xmlread(lut); nodes=dom.getElementsByTagName('summaryimagefile');
            for j=0:nodes.getLength-1
                rel=strtrim(char(nodes.item(j).getTextContent())); rel=regexprep(rel,'^[/\\]+','');
                img=fullfile(root{1},rel);
                if ~isfile(img)
                    if isfile([img '.nii.gz']), img=[img '.nii.gz']; elseif isfile([img '.nii']), img=[img '.nii']; else, continue; end
                end
                [~,nm]=fileparts(regexprep(img,'\.gz$',''));
                P(end+1)=entry(['FSL: ' nm],img,lut,'xml','FSL'); %#ok<AGROW>
            end
        catch ME
            warning('mva:atlasDiscovery','Cannot read %s: %s',lut,ME.message);
        end
    end
end
if isempty(P), return; end
[~,ix]=unique({P.img},'stable'); P=P(ix);
priority=2*ones(1,numel(P)); priority(strcmp({P.source},'CAT12'))=1;
priority(contains(lower(string({P.name})),'neuromorphometrics'))=0;
[~,ix]=sort(priority); P=P(ix);
end
function p=entry(name,img,lut,typ,source)
p=struct('name',name,'img',img,'lut',lut,'lutType',typ,'mode','maxprob','source',source);
end
