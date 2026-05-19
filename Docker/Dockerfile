# Dockerfile - IsoGSM Docker image
#
# Author : Shohei Aoki
# License: MIT
#
# Provides a complete build environment for IsoGSM on Ubuntu 22.04:
#   - Intel oneAPI ifort 2023.x
#   - OpenMPI 5.0.10
#   - wgrib2 v3.1.3
#   - GrADS, CDO, NCO
#   - Python scientific stack (NumPy, Pandas, xarray, netCDF4, SciPy, Matplotlib)

FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Intel oneAPI repository
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl gnupg ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://apt.repos.intel.com/intel-gpg-keys/GPG-PUB-KEY-INTEL-SW-PRODUCTS.PUB \
         -o /tmp/intel-gpg-key.pub && \
    gpg --dearmor < /tmp/intel-gpg-key.pub > /usr/share/keyrings/oneapi-archive-keyring.gpg && \
    rm /tmp/intel-gpg-key.pub && \
    echo "deb [signed-by=/usr/share/keyrings/oneapi-archive-keyring.gpg] https://apt.repos.intel.com/oneapi all main" \
         > /etc/apt/sources.list.d/oneAPI.list

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 python3-pip python3-dev \
    cdo nco grads \
    wget patch \
    build-essential gfortran \
    intel-oneapi-compiler-fortran=2023.* \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Build OpenMPI with ifort
SHELL ["/bin/bash", "-c"]
WORKDIR /usr/local/src
RUN wget https://download.open-mpi.org/release/open-mpi/v5.0/openmpi-5.0.10.tar.gz -O openmpi.tgz && \
    tar -zxvf openmpi.tgz && \
    cd openmpi-5.0.10 && \
    source /opt/intel/oneapi/setvars.sh && \
    export FC=ifort && \
    ./configure --prefix=/usr/local/openmpi && \
    make -j$(nproc) && \
    make install && \
    cd / && rm -rf /usr/local/src/*
SHELL ["/bin/sh", "-c"]

RUN ln -s /usr/bin/python3 /usr/bin/python

WORKDIR /data

RUN echo "export PATH=/root/.local/bin:/usr/local/openmpi/bin:$PATH" >> /root/.bashrc && \
    echo "source /opt/intel/oneapi/setvars.sh" >> /root/.bashrc

CMD ["/bin/bash"]
