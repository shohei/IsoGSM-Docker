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
#  System profile is detected automatically from the runtime environment:
#
#    ompi5 -- OpenMPI 5.x (PRRTE runtime) or /dev/shm < 512 MB
#               isogsm.patch     : PBS_O_WORKDIR guard in roses/guns HEADER
#               isogsm_run.patch : hostfile slots= format;
#                                  OMPI_MCA_btl_sm_backing_directory=/tmp
#                                  (prevents SIGBUS in Alltoallv when /dev/shm
#                                  is at the 64 MB Docker default);
#                                  --allow-run-as-root --map-by :OVERSUBSCRIBE
#                                  (OpenMPI 5 PRRTE does not reliably honour
#                                  slots=N in the hostfile)
#
#    ompi4 -- OpenMPI 4.x or earlier (default)
#               isogsm_run.patch : standard @MPIEXEC@ template with
#                                  -hostfile / -wdir options only
#
#  Patch application order:
#    1. <profile>/isogsm.patch     -- applied before build
#    2. configure-scr              -- generates gsm_runs run scripts
#    3. <profile>/isogsm_run.patch -- applied after configure-scr
#

ISOGSM_DIR="${1:-/data/IsoGSM}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# --- detect system profile ---
detect_profile() {
    local ompi_major
    ompi_major=$(mpirun --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 | cut -d. -f1)
    if [ -n "$ompi_major" ] && [ "$ompi_major" -ge 5 ]; then
        echo "ompi5"
        return
    fi

    local shm_kb
    shm_kb=$(df /dev/shm 2>/dev/null | awk 'NR==2{print $2}')
    if [ -n "$shm_kb" ] && [ "$shm_kb" -lt 524288 ]; then
        echo "ompi5"
        return
    fi

    echo "ompi4"
}

PROFILE=$(detect_profile)
PATCH_FILE="$SCRIPT_DIR/$PROFILE/isogsm.patch"
RUN_PATCH_FILE="$SCRIPT_DIR/$PROFILE/isogsm_run.patch"

echo "=== IsoGSM build ==="
echo "ISOGSM_DIR    : $ISOGSM_DIR"
echo "PROFILE       : $PROFILE"
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
echo ""
echo "NOTE: IsoGSM initial conditions"
echo "  fcst_t62k28_n128.x requires a 4-tracer sigma file (sigit/sigitdt)."
echo "  The standard sigft*.asc has only 1 tracer; chgr converts it to"
echo "  a 1-tracer binary.  On first run, place a pre-spun 4-tracer sigit"
echo "  and sigitdt in the run directory (gsm_runs/g_000/) before running"
echo "  ./gsm.  After a successful 72-h forecast completes, sigit is"
echo "  automatically updated to the 4-tracer model output and subsequent"
echo "  restarts work without intervention."
