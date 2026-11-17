function T=mva_review_assignments(T)
% Simple editable review; candidate lists are shown for ambiguous inputs.
f=uifigure('Name','MRS acquisitions and file assignments','Position',[80 100 1280 620]);
g=uigridlayout(f,[4 1]); g.RowHeight={130,'1x',70,'fit'};
groups=unique(T.Acquisition,'stable'); data=cell(numel(groups),3);
for k=1:numel(groups)
    ix=strcmp(T.Acquisition,groups{k}); data(k,:)={any(T.Include(ix)),groups{k},T.ROI{find(ix,1)}};
end
rt=uitable(g,'Data',data,'ColumnName',{'Analyse','Detected acquisition','ROI name'}, ...
    'ColumnEditable',[true false true],'ColumnWidth',{70,200,200},'CellEditCallback',@mapEdit);
ut=uitable(g,'Data',T(:,1:10),'ColumnEditable',[true false false false true true false true false false], ...
    'ColumnWidth',{55,90,75,90,90,240,240,240,90,300},'CellEditCallback',@rowEdit,'CellSelectionCallback',@selectCell);
info=uitextarea(g,'Editable','off','Value',{'Water references are ignored. Select a T1 cell to choose among candidates, or edit/paste an MRS/T1 path.'});
b=uibutton(g,'Text','Done','ButtonPushedFcn',@done);
f.CloseRequestFcn=@done;
uiwait(f);
if isvalid(f), delete(f); end
    function mapEdit(~,event)
        row=event.Indices(1); col=event.Indices(2); ix=strcmp(T.Acquisition,groups{row});
        if col==1, T.Include(ix)=logical(event.NewData);
        elseif col==3, T.ROI(ix)={char(event.NewData)}; end
        T=mva_validate_assignments(T); ut.Data=T(:,1:10);
    end
    function rowEdit(~,~)
        T(:,1:10)=ut.Data; T=mva_validate_assignments(T); ut.Data=T(:,1:10);
    end
    function selectCell(~,event)
        if isempty(event.Indices), return; end
        row=event.Indices(1,1); col=event.Indices(1,2);
        info.Value={T.Note{row}};
        if col==7, info.Value={'Separate water references ignored: localisation only'}; return;
        elseif col==8, choices=T.T1Candidates{row}; field='T1';
        else, return; end
        if numel(choices)>1
            [ix,ok]=listdlg('ListString',choices,'SelectionMode','single','PromptString',['Choose ' field],'ListSize',[850 200]);
            if ok, T.(field){row}=choices{ix}; T=mva_validate_assignments(T); ut.Data=T(:,1:10); end
        end
    end
    function done(~,~)
        T=mva_validate_assignments(T); uiresume(f);
    end
end
