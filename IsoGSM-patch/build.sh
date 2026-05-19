#!/bin/bash
set -e

#
#  build.sh - IsoGSM build script
#
#  Author : Shohei Aoki
#  License: MIT
#
#  Usage: ./build.sh [ISOGSM_DIR]
#
#  ISOGSM_DIR : IsoGSM source root (default: /data/IsoGSM)
#
#  Patch selection is determined independently by two runtime conditions:
#
#    isogsm.patch     -- selected by PBS presence
#      pbs/   : PBS (qsub) detected; adds PBS_O_WORKDIR guard in roses/guns
#               HEADER so the generated run scripts work both inside and
#               outside a PBS job
#      nopbs/ : no PBS; omits the guard (PBS_O_WORKDIR is never set)
#
#    isogsm_run.patch -- selected by /dev/shm size
#      smallshm/ : /dev/shm < 512 MB (Docker default 64 MB on many HPC nodes);
#                  redirects OpenMPI shared-memory segments to /tmp via
#                  OMPI_MCA_btl_sm_backing_directory to prevent SIGBUS in
#                  Alltoallv; also applies hostfile slots= format and
#                  --allow-run-as-root --map-by :OVERSUBSCRIBE
#      largeshm/ : /dev/shm >= 512 MB; standard @MPIEXEC@ template with
#                  -hostfile / -wdir options only
#
#  Patch application order:
#    1. isogsm.patch     -- applied before build
#    2. configure-scr    -- generates gsm_runs run scripts
#    3. isogsm_run.patch -- applied after configure-scr
#

ISOGSM_DIR="${1:-/data/IsoGSM}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# --- select isogsm.patch: PBS presence ---
if command -v qsub &>/dev/null; then
    PATCH_PROFILE="pbs"
else
    PATCH_PROFILE="nopbs"
fi

# --- select isogsm_run.patch: /dev/shm size ---
_shm_kb=$(df /dev/shm 2>/dev/null | awk 'NR==2{print $2}')
if [ -n "$_shm_kb" ] && [ "$_shm_kb" -lt 524288 ]; then
    RUN_PATCH_PROFILE="smallshm"
else
    RUN_PATCH_PROFILE="largeshm"
fi

# --- detect 9P (WSL2 DrvFs) filesystem ---
#   On WSL2 with /data on the Windows C: drive (DrvFs), stat -f -c%T returns
#   "v9fs".  DrvFs causes two MPI-related problems that the 9pfs patches fix:
#   (1) wrisig concurrent I/O: all MPI ranks call wrisig simultaneously; on
#       v9fs a write-open from one rank immediately truncates the file seen by
#       other ranks, causing forrtl error(24) EOF in setsig/wrisig.
#       isogsm_9pfs_src.patch fixes this in two steps:
#         - gsm/src/fcst/wrisig.F: adds "#ifdef MP" guard so only rank 0
#           writes restart files (uses /commpi/ common block for mype).
#         - gsm/src/fcst_par/Makefile.in: adds -DMP to CPP so the #ifdef
#           guard is active when the MPI binary is compiled.
#   (2) Large sequential I/O (chgr outputs, OpenMPI shared-memory backing) is
#       unreliable on v9fs; isogsm_9pfs.patch routes those paths through /tmp.
_fstype=$(stat -f -c%T "$ISOGSM_DIR" 2>/dev/null)
FS_9P_PATCH_FILE=""
FS_9P_SRC_PATCH_FILE=""
if [ "$_fstype" = "v9fs" ]; then
    FS_9P_PATCH_FILE="$SCRIPT_DIR/9pfs/isogsm_9pfs.patch"
    FS_9P_SRC_PATCH_FILE="$SCRIPT_DIR/9pfs/isogsm_9pfs_src.patch"
fi

PATCH_FILE="$SCRIPT_DIR/$PATCH_PROFILE/isogsm.patch"
RUN_PATCH_FILE="$SCRIPT_DIR/$RUN_PATCH_PROFILE/isogsm_run.patch"

echo "=== IsoGSM build ==="
echo "ISOGSM_DIR      : $ISOGSM_DIR"
echo "PATCH_PROFILE   : $PATCH_PROFILE  (isogsm.patch)"
echo "RUN_PATCH_PROFILE: $RUN_PATCH_PROFILE  (isogsm_run.patch)"
echo "FS_TYPE         : ${_fstype:-unknown}"
echo "PATCH_FILE      : $PATCH_FILE"
echo "RUN_PATCH_FILE  : $RUN_PATCH_FILE"
if [ -n "$FS_9P_PATCH_FILE" ]; then
    echo "9P_PATCH_FILE   : $FS_9P_PATCH_FILE"
    echo "9P_SRC_PATCH_FILE: $FS_9P_SRC_PATCH_FILE"
fi

# --- sanity checks ---
if [ ! -d "$ISOGSM_DIR" ]; then
    echo "ERROR: IsoGSM directory not found: $ISOGSM_DIR"
    exit 1
fi
if [ ! -f "$PATCH_FILE" ]; then
    echo "ERROR: patch file not found: $PATCH_FILE"
    exit 1
fi
if [ ! -f "$RUN_PATCH_FILE" ]; then
    echo "ERROR: runtime patch file not found: $RUN_PATCH_FILE"
    exit 1
fi

apply_patch() {
    local pfile="$1"
    local label="$2"
    cd "$ISOGSM_DIR"
    if patch -p1 --dry-run < "$pfile" > /dev/null 2>&1; then
        patch -p1 < "$pfile"
        echo "$label applied successfully."
    elif patch -p1 --dry-run -R < "$pfile" > /dev/null 2>&1; then
        echo "$label already applied, skipping."
    else
        echo "ERROR: $label failed. Please check the source tree."
        patch -p1 --dry-run < "$pfile"
        exit 1
    fi
}

# --- apply build-time patch ---
echo ""
echo "--- applying build-time patch (isogsm.patch) ---"
apply_patch "$PATCH_FILE" "isogsm.patch"

# --- setup Intel oneAPI environment ---
echo ""
echo "--- setting up Intel oneAPI environment ---"
SETVARS=/opt/intel/oneapi/setvars.sh
if [ -f "$SETVARS" ]; then
    # setvars.sh requires bash
    source "$SETVARS" --force
else
    echo "WARNING: $SETVARS not found; assuming environment is already set."
fi

export PATH=/usr/local/openmpi/bin:$PATH
export LD_LIBRARY_PATH=/usr/local/openmpi/lib:${LD_LIBRARY_PATH:-}

# --- configure and build LIBS ---
echo ""
echo "--- configuring LIBS ---"
cd "$ISOGSM_DIR/libs"
./configure-libs

echo ""
echo "--- building LIBS ---"
make clean
make

# --- apply 9P source patch before GSM build (WSL2 DrvFs only) ---
if [ -n "$FS_9P_SRC_PATCH_FILE" ]; then
    echo ""
    echo "--- applying 9P source patch (isogsm_9pfs_src.patch) ---"
    apply_patch "$FS_9P_SRC_PATCH_FILE" "isogsm_9pfs_src.patch"
fi

# --- configure and build GSM ---
echo ""
echo "--- configuring GSM ---"
cd "$ISOGSM_DIR/gsm"
export NPES=$(nproc)
echo "NPES set to $NPES (nproc)"
./configure-model

echo ""
echo "--- building GSM ---"
make clean
make

# --- configure gsm_runs (generates gsm_runs/gsm from expscr template) ---
echo ""
echo "--- configuring gsm_runs (generating run scripts) ---"
cd "$ISOGSM_DIR/gsm_runs"
NOASK=on ./configure-scr gsm

# --- apply runtime patch ---
echo ""
echo "--- applying runtime patch (isogsm_run.patch) ---"
apply_patch "$RUN_PATCH_FILE" "isogsm_run.patch"

# --- apply 9P filesystem patch (WSL2 DrvFs only) ---
if [ -n "$FS_9P_PATCH_FILE" ]; then
    echo ""
    echo "--- applying 9P filesystem patch (isogsm_9pfs.patch) ---"
    if [ ! -f "$FS_9P_PATCH_FILE" ]; then
        echo "ERROR: 9P patch file not found: $FS_9P_PATCH_FILE"
        exit 1
    fi
    apply_patch "$FS_9P_PATCH_FILE" "isogsm_9pfs.patch"
fi

# --- create $HOME/node_list for standalone MPI execution ---
echo ""
echo "--- creating \$HOME/node_list ---"
NPES=${NPES:-$(nproc)}
python3 -c "print('\n'.join(['localhost']*$NPES))" > "$HOME/node_list"
echo "node_list created at $HOME/node_list ($NPES localhost entries)."

echo ""
echo "=== build complete ==="
echo ""
echo "NOTE: IsoGSM initial conditions"
echo "  The forecast binary (fcst_t62k28_n${NPES}.x) is compiled with 4"
echo "  isotope tracers.  The standard sigft*.asc initial condition has only"
echo "  1 tracer (water vapour); chgr converts it to a 1-tracer binary and"
echo "  rdsig zero-initialises the 3 missing isotope fields automatically."
echo "  No pre-spun 4-tracer file is needed for the first run.  After a"
echo "  successful 72-h forecast, sigit is updated to the full 4-tracer"
echo "  model output and subsequent restarts use the model-generated isotopes."
