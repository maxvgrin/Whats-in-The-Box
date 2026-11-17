function out = mva_resample_to_ref(vol, mat, refMat, refDim, interp)
% INPUT
%   vol     - 3D source array
%   mat     - source voxel(1-based)->world(mm) affine (4x4)
%   refMat  - reference voxel(1-based)->world(mm) affine (4x4)
%   refDim  - reference dimensions [nx ny nz]
%   interp  - 0 nearest-neighbour (for label maps)
%             1 trilinear        (for continuous/probability maps)
%
% Each reference voxel is mapped to world mm (refMat), then to source voxel
% coordinates (inv(mat)), and the source is sampled there. BOTH affines must
% describe the SAME world space (e.g. both MNI). Samples outside the source
% volume are set to 0.

    if nargin < 5, interp = 0; end
    refDim = double(refDim(:)');

    % world mm coordinate of every reference voxel
    [I,J,K] = ndgrid(1:refDim(1), 1:refDim(2), 1:refDim(3));
    N      = numel(I);
    voxRef = [I(:)'; J(:)'; K(:)'; ones(1,N)];
    world  = refMat * voxRef;          % 4 x N
    voxSrc = mat \ world;              % 4 x N  (1-based source voxel coords)

    xs = reshape(voxSrc(1,:), refDim); % source dim1 (rows)
    ys = reshape(voxSrc(2,:), refDim); % source dim2 (cols)
    zs = reshape(voxSrc(3,:), refDim); % source dim3 (pages)

    if interp == 0
        xi = round(xs); yi = round(ys); zi = round(zs);
        inb = xi>=1 & xi<=size(vol,1) & ...
              yi>=1 & yi<=size(vol,2) & ...
              zi>=1 & zi<=size(vol,3);
        out = zeros(refDim);
        out(inb) = vol(sub2ind(size(vol), xi(inb), yi(inb), zi(inb)));
    else
        % interp3 grid convention: X<->cols(dim2), Y<->rows(dim1), Z<->pages
        out = interp3(vol, ys, xs, zs, 'linear', 0);
    end
end
