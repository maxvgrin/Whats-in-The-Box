#!/bin/bash
# Double-click this file (macOS) to launch the MRS Atlas Composition GUI.
# It starts MATLAB and opens the front end. You can also just type
#   mrs_atlas_gui
# at the MATLAB prompt from this folder.
DIR="$(cd "$(dirname "$0")" && pwd)"
if command -v matlab >/dev/null 2>&1; then
    MATLAB="matlab"
else
    MATLAB="$(ls -d /Applications/MATLAB_R*.app/bin/matlab 2>/dev/null | sort | tail -1)"
fi
if [ -z "$MATLAB" ]; then
    echo "Could not find MATLAB. Open MATLAB manually, cd to:"
    echo "    $DIR"
    echo "and run:  mrs_atlas_gui"
    read -r -p "Press Enter to close."
    exit 1
fi
# Atlas presets resolve paths from $FSLDIR/data/atlases. If it isn't already
# set in the environment, point it at the local atlas install so the presets
# work out of the box (otherwise the GUI reports "Atlas not found").
if [ -z "$FSLDIR" ] && [ -d "$HOME/mrs_deps/atlas/data/atlases" ]; then
    FSLDIR="$HOME/mrs_deps/atlas"
fi
# SPM12 and Osprey must be on the MATLAB path; add the local installs if present
# (otherwise the GUI reports "SPM12 not found on the path. Set cfg.spmPath.").
SPM_DIR="$HOME/mrs_deps/spm12"
OSPREY_DIR="$HOME/mrs_deps/osprey"
PRE="if ~isempty('$FSLDIR'), setenv('FSLDIR','$FSLDIR'); end;"
[ -f "$SPM_DIR/spm.m" ]      && PRE="$PRE addpath('$SPM_DIR');"
[ -d "$OSPREY_DIR" ]         && PRE="$PRE addpath(genpath('$OSPREY_DIR'));"
exec "$MATLAB" -r "$PRE cd('$DIR'); mrs_atlas_gui;"
