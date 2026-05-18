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

# Intel oneAPI リポジトリ追加に必要なツールを先にインストール
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    gnupg \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Intel oneAPI の GPG キーをファイルに保存してから dearmor（パイプ失敗を回避）
RUN curl -fsSL https://apt.repos.intel.com/intel-gpg-keys/GPG-PUB-KEY-INTEL-SW-PRODUCTS.PUB \
         -o /tmp/intel-gpg-key.pub && \
    gpg --dearmor < /tmp/intel-gpg-key.pub > /usr/share/keyrings/oneapi-archive-keyring.gpg && \
    rm /tmp/intel-gpg-key.pub && \
    echo "deb [signed-by=/usr/share/keyrings/oneapi-archive-keyring.gpg] https://apt.repos.intel.com/oneapi all main" \
         > /etc/apt/sources.list.d/oneAPI.list

# 1. 基本ツールのインストール
RUN apt-get update && apt-get install -y \
    python3 \
    python3-pip \
    python3-dev \
    cdo \
    nco \
    git \
    wget \
    cmake \
    build-essential \
    gfortran \
    vim \
    htop \
    ubuntu-restricted-extras \
    make \
    gcc \
    xauth \
    xorg \
    subversion \
    intel-oneapi-compiler-fortran=2023.* \
    grads \
    cvs \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# 2. wgrib2 を公式から取得し、AECを無効化してコンパイル
WORKDIR /usr/local/src
RUN wget https://ftp.cpc.ncep.noaa.gov/wd51we/wgrib2/wgrib2.tgz.v3.1.3 -O wgrib2.tgz && \
    tar -zxvf wgrib2.tgz && \
    cd grib2 && \
    sed -i 's/USE_AEC=1/USE_AEC=0/g' makefile && \
    export CC=gcc && \
    export FC=gfortran && \
    export FFLAGS="-O2 -fallow-argument-mismatch" && \
    export FCFLAGS="-O2 -fallow-argument-mismatch" && \
    make -j$(nproc) && \
    cp wgrib2/wgrib2 /usr/local/bin/ && \
    cd / && rm -rf /usr/local/src/*

# シェルを一時的に sh から bash に切り替える
SHELL ["/bin/bash", "-c"]

WORKDIR /usr/local/src

# source と、それに続くビルドコマンドを「&&」で繋いで1つの RUN で実行する
RUN wget https://download.open-mpi.org/release/open-mpi/v5.0/openmpi-5.0.10.tar.gz -O openmpi.tgz && \
    tar -zxvf openmpi.tgz && \
    cd openmpi-5.0.10 && \
    source /opt/intel/oneapi/setvars.sh && \
    export FC=ifort && \
    ./configure --prefix=/usr/local/openmpi && \
    make -j$(nproc) && \
    make install && \
    cd / && rm -rf /usr/local/src/*

# 必要に応じて、これ以降のシェルの設定をデフォルト（sh）に戻す（任意）
SHELL ["/bin/sh", "-c"]

# Install claude code (optional)
#RUN curl -fsSL https://claude.ai/install.sh | bash

# 3. python3 を python として呼び出せるようにリンクを作成
RUN ln -s /usr/bin/python3 /usr/bin/python

# 4. Pythonのデータ解析・気象系ライブラリの導入
RUN pip3 install --no-cache-dir \
    numpy \
    pandas \
    xarray \
    netCDF4 \
    scipy \
    matplotlib

WORKDIR /data

RUN echo "export PATH=/root/.local/bin:/usr/local/openmpi/bin:$PATH" >> /root/.bashrc
RUN echo "source /opt/intel/oneapi/setvars.sh" >> /root/.bashrc

CMD ["/bin/bash"]
