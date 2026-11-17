function gz = mva_compress_nifti(p)
p=char(p);
if endsWith(lower(p),'.gz'), assert(isfile(p),'Missing output: %s',p); gz=p; return; end
assert(isfile(p),'Missing output: %s',p);
g=gzip(p); gz=g{1};
assert(isfile(gz),'Compression failed: %s',p);
delete(p);
end
