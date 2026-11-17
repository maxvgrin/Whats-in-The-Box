function T=mva_validate_assignments(T)
T.Reference(:)={''};
if ismember('ReferenceCandidates',T.Properties.VariableNames)
    T.ReferenceCandidates=repmat({{}},height(T),1);
end
for k=1:height(T)
    T.ROI{k}=strtrim(T.ROI{k});
    first=find(strcmpi(T.ROI,T.ROI{k}),1);
    T.ROI{k}=T.ROI{first};
end
for k=1:height(T)
    if ~T.Include(k), continue; end
    if startsWith(T.Note{k},'Mixed DICOM/IMA/RDA folder'), T.Status{k}='Choose file'; continue; end
    T.Status{k}='OK';
    if isempty(T.ROI{k}) || strcmp(T.ROI{k},'Unassigned') || isempty(regexp(T.ROI{k},'^[A-Za-z0-9][A-Za-z0-9_-]*$','once'))
        T.Status{k}='Choose file'; T.Note{k}='ROI must be a simple name: letters, numbers, underscore or hyphen';
    elseif ~(isfile(T.MRS{k}) || isfolder(T.MRS{k})) || ~isfile(T.T1{k})
        T.Status{k}='Missing'; T.Note{k}='Select existing MRS and T1 inputs';
    elseif sum(T.Include & strcmp(T.Subject,T.Subject{k}) & strcmpi(T.ROI,T.ROI{k}))>1
        T.Status{k}='Choose file'; T.Note{k}='Choose one acquisition per participant/ROI (including across sessions)';
    end
end
end
