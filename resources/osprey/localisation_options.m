% OspreyJob initialization fields, following Osprey's example jobTwix.m:
% https://github.com/schorschinho/osprey/blob/develop/exampledata/twix/UnEdited/jobTwix.m
% OspreyJob reads fit.style/method even for a localisation-only workflow.
% These fields DO NOT execute fitting. This toolbox calls only Job/Load/Coreg.
opts = struct();
opts.SpecReg = 'none';
opts.SubSpecAlignment.mets = 'none';
opts.SubSpecAlignment.mm = 'none';
opts.ECC.raw = 0;
opts.ECC.mm = 0;
opts.savePDF = 0;
opts.saveLCM = 0;
opts.savejMRUI = 0;
opts.saveJMRUI = 0;
opts.saveVendor = 0;
opts.saveNII = 0;
opts.exportParams.flag = 0;
opts.exportParams.path = '';
opts.fit.method = 'Osprey';
opts.fit.includeMetabs = {'default'};
opts.fit.style = 'Separate';
opts.fit.range = [0.5 4];
opts.fit.rangeWater = [2.0 7.4];
opts.fit.bLineKnotSpace = 0.4;
opts.fit.fitMM = 1;
opts.img.deface = 0;
