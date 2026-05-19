# IsoGSM on Docker

> Dockerized environment for running **IsoGSM** — the Isotope-enabled Global Spectral Model for atmospheric water isotope simulations.

---

## Overview

This repository provides a ready-to-use Docker setup for IsoGSM, a global atmospheric model that tracks water isotopes (HDO, H₂¹⁸O). The Docker image bundles all required dependencies so you can build and run IsoGSM without manually configuring a complex Fortran/MPI environment.

**What's included in the Docker image:**

| Component | Version |
|---|---|
| Base OS | Ubuntu 22.04 |
| Fortran compiler | Intel oneAPI ifort 2023.x |
| MPI | OpenMPI 5.0.10 |

---

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/) installed and running
- `subversion` and `wget` available on the host (used during source checkout)

> [!WARNING]
> **x86\_64 (amd64) only.** This image relies on the Intel oneAPI Fortran compiler and is **not compatible with ARM64 processors**, including Apple Silicon (M1/M2/M3/M4). Use an x86\_64 Linux machine or a cloud VM (e.g. AWS EC2, Google Cloud) instead.

---

## Quick Start

### Linux / macOS / WSL (Windows)

Run the one-liner installer:

```bash
curl -fsSL https://tinyurl.com/isogsm-docker | bash
```

This script will:
1. Check out the IsoGSM source via SVN
2. Pull the pre-built Docker image
3. Launch a container with the source tree mounted at `/data/IsoGSM`
4. Download and apply the build patches
5. Compile IsoGSM inside the container

> [!IMPORTANT]
> **Volume mount:** The IsoGSM source directory checked out on the **host** (`IsoGSM/`) is mounted into the container as **`/data/IsoGSM`**.
> Files edited on the host are immediately visible inside the container, and vice versa.
> Do **not** delete the host-side `IsoGSM/` directory while the container is running.

### Re-entering the container

After the initial setup, use the following command to re-attach to the running container:

```bash
docker exec -it isogsm /bin/bash
```

> [!NOTE]
> `docker exec` only works while the container is **running**. If the container has been stopped (e.g. after a reboot), start it first:
> ```bash
> docker start isogsm
> docker exec -it isogsm /bin/bash
> ```

---

## Repository Structure

```
IsoGSM-Docker/
├── Docker/
│   └── Dockerfile               # Ubuntu 22.04 + Intel oneAPI + OpenMPI
├── IsoGSM-patch/
│   ├── build.sh                        # Build driver (detects environment, applies patches, compiles)
│   ├── pbs/isogsm.patch                # Source patch — PBS present
│   ├── nopbs/isogsm.patch              # Source patch — no PBS
│   ├── smallshm/isogsm_run.patch       # Runtime patch — /dev/shm < 512 MB
│   ├── largeshm/isogsm_run.patch       # Runtime patch — /dev/shm ≥ 512 MB
│   └── 9pfs/
│       ├── isogsm_9pfs_src.patch       # Fortran source patch for WSL2 DrvFs
│       └── isogsm_9pfs.patch           # Runtime script patch for WSL2 DrvFs
└── install.sh                          # One-liner installer entry point
```

---

## Automatic Patch Selection

`build.sh` selects the appropriate patch variant for each patch file independently, based on two runtime conditions detected inside the container.

### `isogsm.patch` — selected by PBS presence

| Condition | Variant | What it changes |
|---|---|---|
| `qsub` found in `PATH` | `pbs/` | Adds a guard `[ -n "$PBS_O_WORKDIR" ] && cd "$PBS_O_WORKDIR"` in the roses/guns job-script HEADER, so the generated run scripts work both inside and outside a PBS job |
| `qsub` not found | `nopbs/` | Omits the guard (`$PBS_O_WORKDIR` is never set on non-PBS machines) |

### `isogsm_run.patch` — selected by `/dev/shm` size

| Condition | Variant | What it changes |
|---|---|---|
| `/dev/shm` < 512 MB | `smallshm/` | Sets `OMPI_MCA_btl_sm_backing_directory=/tmp` to redirect OpenMPI shared-memory segments away from the constrained `/dev/shm` (default 64 MB in Docker), preventing SIGBUS in `MPI_Alltoallv`; also applies `--allow-run-as-root`, `--map-by :OVERSUBSCRIBE`, and `slots=` hostfile format |
| `/dev/shm` ≥ 512 MB | `largeshm/` | Uses the standard `@MPIEXEC@` template with `-hostfile` and `-wdir` options only |

The two conditions are evaluated independently, so all four combinations are handled correctly.

```
           /dev/shm < 512 MB    /dev/shm >= 512 MB
          ┌─────────────────────┬──────────────────────┐
PBS found │ pbs + smallshm      │ pbs + largeshm        │
no PBS    │ nopbs + smallshm    │ nopbs + largeshm      │
          └─────────────────────┴──────────────────────┘
```

### WSL2 DrvFs (9P filesystem) patches — applied when `/data/IsoGSM` is on a 9P filesystem

When running on **WSL2 with the IsoGSM source on the Windows filesystem** (e.g. `C:\`), the bind-mounted volume uses the **DrvFs / 9P protocol** (`v9fs`). This filesystem lacks the Linux page cache, which causes two classes of failure:

- **Fortran binary writes are dropped or truncated.** Large unformatted writes that fit in the page cache on a native Linux filesystem are silently lost on 9P because there is no write-back buffer.
- **Concurrent MPI file access is unsafe.** File truncation by one process is immediately visible to all other MPI ranks, corrupting sigma files written during the forecast.

`build.sh` detects this condition by checking `stat -f -c%T "$ISOGSM_DIR"`. If the result is `v9fs`, two additional patches are applied:

| Patch file | Applied | What it fixes |
|---|---|---|
| `9pfs/isogsm_9pfs_src.patch` | Before GSM build | **`gsm/src/fcst_par/Makefile.in`**: appends `-DMP` to `CPP`, activating the pre-existing `#ifdef MP / if (mype.eq.master)` guard in `wrisig.F` so that only MPI rank 0 writes sigma files — eliminating the race where every rank simultaneously opens the file for writing (which on v9fs truncates it immediately). **`gsm/src/fcst/wrisig.F`**: adds an `iorog_read` read-once flag around the `sigit` open/read block so the orog array is loaded only on the first call; this prevents the `itpdt=4` write path from truncating `sigit` just before the `itpdt=5` call tries to read it back for topography. |
| `9pfs/isogsm_9pfs.patch` | After `configure-scr` | **`chgr`/`chgr.in`**: routes sigma file output through a `tmpfs` temporary file (`/tmp/chgr_*`), then copies back after the converter exits — ensuring writes land on a page-cached filesystem. **`mpisub`/`mpisub.in`**: copies the entire run directory to a `tmpfs` scratch directory (`/tmp/isogsm_*`), executes MPI there, then copies output files back to the original location. |

These patches are **only applied on 9P filesystems** and are a no-op on native Linux or Docker-on-Linux environments.

---

## Credits

### IsoGSM Model

IsoGSM was developed by **Kei Yoshimura** and collaborators at the University of Tokyo. If you use IsoGSM in your research, please cite the original publication:

> Yoshimura, K., Kanamitsu, M., Noone, D., & Oki, T. (2008). Historical isotope simulation using Reanalysis atmospheric data. *Journal of Geophysical Research: Atmospheres*, 113, D19108. https://doi.org/10.1029/2008JD010074

### Docker Environment

Docker packaging and build automation by **Shohei Aoki** at Jomo Kenyatta University of Agriculture and Technology.

---

## License

The Docker configuration files in this repository are provided under the [MIT License](LICENSE).  
IsoGSM source code is subject to its own license — please refer to the IsoGSM distribution.