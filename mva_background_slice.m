function slice = mva_background_slice(bg,kind,fixed,x,y)
[X,Y]=meshgrid(x,y); F=repmat(fixed,size(X));
switch kind
    case 'sag', world=[F(:)';X(:)';Y(:)'];
    case 'cor', world=[X(:)';F(:)';Y(:)'];
    otherwise, world=[X(:)';Y(:)';F(:)'];
end
v=bg.mat\[world;ones(1,numel(X))];
slice=reshape(interpn(double(bg.img),v(1,:),v(2,:),v(3,:),'linear',0),size(X));
slice(~isfinite(slice))=0;
end
