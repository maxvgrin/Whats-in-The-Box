function V = mva_read_data(p)
[p,cleanup]=mva_temp_nii(p); %#ok<ASGLU>
h=spm_vol(p); h=h(1);
V=struct('img',spm_read_vols(h),'mat',h.mat,'dim',h.dim(1:3));
end
