function V = mva_read_vol(fpath, volIdx)
%   V = mva_read_vol(fpath)        reads all volumes (4D -> 4D array)
%   V = mva_read_vol(fpath, n)     reads only volume n
%
% OUTPUT struct V:
%   V.img   - image data (double)             [nx ny nz (x nvol)]
%   V.mat   - 4x4 voxel(1-based)->world(mm) affine
%   V.dim   - [nx ny nz]
%   V.fname - path actually read (a temp .nii if the input was gzipped)
%   V.gz    - true if a temporary gunzipped file/dir was created
%
% SPM's spm_vol cannot read .gz directly, so .nii.gz inputs are transparently
% gunzipped to a temporary file. If V.gz is true the caller may delete
% fileparts(V.fname) when finished.

    if nargin < 2, volIdx = []; end
    V = struct('img',[],'mat',[],'dim',[],'fname','','gz',false);

    fpath = char(fpath);
    if exist(fpath,'file') ~= 2
        error('mva:fileNotFound','File not found: %s', fpath);
    end

    [~,~,e] = fileparts(fpath);
    if strcmpi(e,'.gz')
        tmpDir = tempname; mkdir(tmpDir);
        g = gunzip(fpath, tmpDir);   % cellstr of unzipped files
        fpath = g{1};
        V.gz  = true;
    end
    V.fname = fpath;

    hdr = spm_vol(fpath);            % struct array, one entry per volume
    if ~isempty(volIdx)
        hdr = hdr(volIdx);
    end
    V.mat = hdr(1).mat;
    V.dim = hdr(1).dim(1:3);
    V.img = spm_read_vols(hdr);      % double
end
