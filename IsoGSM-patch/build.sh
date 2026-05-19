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
#  Patch application order:
#    1. isogsm.patch     -- applied before build (source/config changes)
#         - def/get_scrvars       : fix relative path for scrvars sourcing
#         - def/sysvars.defs      : set GRSM_BASE_DIR, MPICH_DIR (Open MPI),
#                                   MPI compiler/flags, PBS_O_WORKDIR guard in
#                                   roses/guns HEADER
#         - gsm/configure-model   : set LIBS_DIR, NPES=$(nproc), NCOL auto
#    2. isogsm_run.patch -- applied after build  (gsm_runs runtime changes)
#         - gsm_runs/runscr/mpisub.in : hostfile Open MPI 5 format, prog path,
#                                       mpirun flags (@MPIEXEC@ template)
#         - gsm_runs/runscr/mpisub    : same, plus --allow-run-as-root,
#                                       --map-by :OVERSUBSCRIBE,
#                                       --mca btl_sm_backing_directory /tmp
#                                       (workaround for 64 MB /dev/shm limit
#                                        in container environments)
#

ISOGSM_DIR="${1:-/data/IsoGSM}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PATCH_FILE="$SCRIPT_DIR/isogsm.patch"
RUN_PATCH_FILE="$SCRIPT_DIR/isogsm_run.patch"

echo "=== IsoGSM build ==="
echo "ISOGSM_DIR    : $ISOGSM_DIR"
echo "PATCH_FILE    : $PATCH_FILE"
echo "RUN_PATCH_FILE: $RUN_PATCH_FILE"

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

# --- create $HOME/node_list for standalone MPI execution ---
echo ""
echo "--- creating \$HOME/node_list ---"
NPES=${NPES:-$(nproc)}
python3 -c "print('\n'.join(['localhost']*$NPES))" > "$HOME/node_list"
echo "node_list created at $HOME/node_list ($NPES localhost entries)."

echo ""
echo "=== build complete ==="
