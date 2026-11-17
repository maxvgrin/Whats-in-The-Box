function [p, cleanup] = mva_temp_nii(p)
p=char(p); cleanup=[];
if ~isfile(p) && isfile([p '.gz']), p=[p '.gz']; end
if ~isfile(p), error('mva:fileNotFound','File not found: %s',p); end
if endsWith(lower(p),'.gz')
    d=tempname; mkdir(d);
    cleanup=onCleanup(@()rmdir(d,'s'));
    g=gunzip(p,d); p=g{1};
end
end
