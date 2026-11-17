function names=mva_read_cat_labels(path)
% CAT label IDs are literal NIfTI intensities, never FSL's index+1.
names=containers.Map('KeyType','double','ValueType','char');
[~,~,ext]=fileparts(path);
if strcmpi(ext,'.xml')
    dom=xmlread(path); items=dom.getElementsByTagName('label');
    for k=0:items.getLength-1
        item=items.item(k); id=str2double(char(item.getAttribute('index')));
        if isnan(id)
            idx=item.getElementsByTagName('index');
            if idx.getLength>0, id=str2double(char(idx.item(0).getTextContent())); end
        end
        nn=item.getElementsByTagName('name');
        if nn.getLength>0, name=strtrim(char(nn.item(0).getTextContent()));
        else, name=strtrim(char(item.getTextContent())); end
        if isfinite(id) && ~isempty(name), names(id)=name; end
    end
else
    % CAT commonly uses semicolon-separated CSV: ROIid;ROIname;...
    T=readtable(path,'FileType','text','VariableNamingRule','preserve');
    v=lower(string(T.Properties.VariableNames));
    vi=find(ismember(v,["value","id","index","roiid","roi_id","label"]),1);
    ni=find(ismember(v,["name","roiname","roi_name","region"]),1);
    if isempty(vi), vi=1; end
    if isempty(ni), ni=min(2,width(T)); end
    ids=str2double(string(T{:,vi})); labels=string(T{:,ni});
    for k=1:numel(ids)
        if isfinite(ids(k)), names(ids(k))=char(labels(k)); end
    end
end
assert(names.Count>0,'No label IDs/names could be read from %s',path);
end
