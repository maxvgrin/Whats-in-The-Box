# What’s in the Box?

**What’s in the Box?** is a MATLAB toolbox for characterizing the anatomical composition and spatial distribution of single-voxel proton MR spectroscopy acquisitions.

The toolbox uses **Osprey** to reconstruct the MRS voxel and **SPM12** for spatial normalization. It quantifies which atlas-defined anatomical regions are contained within each voxel, calculates target occupancy and regional coverage, and generates subject-level composition tables, MNI-space voxel masks, centroid coordinates, and group-level voxel-density maps. Custom atlas definitions can be used. 

## Requirements

The toolbox was developed and tested using:

- **MATLAB R2025b**
- **SPM12 r7771**
- **Osprey develop branch (~v2.9.x)**
- **CAT12** when using the Neuromorphometrics atlas

MATLAB R2020b or newer is expected to support the graphical interface, although the configuration above reflects the environment used during development and testing.

## Getting started

Download or clone the repository, open MATLAB, and set the repository folder as the current working directory or add to path. Make sure SPM12 and Osprey are on the MATLAB path, then start the graphical interface with:

```matlab
start_mrs_atlas
```
For programmatic use, the analysis can be started with:

```matlab
results = run_mrs_atlas_composition(cfg);
```

An example configuration is provided in `example_run.m`.

The toolbox accepts BIDS-organized MRS and corresponding T1-weighted anatomical data, as well as existing Osprey `MRSCont` outputs or Osprey job files. It supports all fileformats that Osprey_Load supports. 
