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
| Visualization | GrADS |
| Data tools | CDO, NCO |
| Python stack | NumPy, Pandas, xarray, netCDF4, SciPy, Matplotlib |

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
docker exec -it isogsm_container /bin/bash
```

> [!NOTE]
> `docker exec` only works while the container is **running**. If the container has been stopped (e.g. after a reboot), start it first:
> ```bash
> docker start isogsm_container
> docker exec -it isogsm_container /bin/bash
> ```

---

## Repository Structure

```
IsoGSM-Docker/
├── Docker/
│   └── Dockerfile          # Ubuntu 22.04 + Intel oneAPI + OpenMPI 
├── IsoGSM-patch/
│   ├── build.sh            # Build driver (applies patches, runs configure & make)
│   ├── isogsm.patch        # Source-level patch applied before build
│   └── isogsm_run.patch    # Runtime patch applied after build
└── install.sh              # One-liner installer entry point
```

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
