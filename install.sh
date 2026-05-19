#!/bin/bash
#
# install.sh - IsoGSM-Docker one-liner installer
#
# Author : Shohei Aoki
# License: MIT
#

# --- check Docker ---
if ! command -v docker &> /dev/null; then
    echo "Error: Docker is not installed."
    echo "Please install Docker first: https://docs.docker.com/get-docker/"
    exit 1
fi

# --- install dependencies if missing ---
MISSING_PKGS=()
command -v svn  &> /dev/null || MISSING_PKGS+=(subversion)
command -v wget &> /dev/null || MISSING_PKGS+=(wget)
if [ ${#MISSING_PKGS[@]} -gt 0 ]; then
    echo "Installing missing packages: ${MISSING_PKGS[*]}"
    sudo apt-get install -y "${MISSING_PKGS[@]}"
fi

svn co svn://210.106.80.235/GRSM/IsoGSM --username guest --password guest123
cd IsoGSM
wget https://raw.githubusercontent.com/shohei/IsoGSM-Docker/refs/heads/main/Docker/Dockerfile
docker build . -t isogsm
docker container stop isogsm_container
docker container rm isogsm_container
docker run -i -v "`pwd`:/data/" --name isogsm_container isogsm << 'EOF'
  set -e
  cd IsoGSM
  wget https://raw.githubusercontent.com/shohei/IsoGSM-Docker/refs/heads/main/IsoGSM-patch/build.sh
  wget https://raw.githubusercontent.com/shohei/IsoGSM-Docker/refs/heads/main/IsoGSM-patch/isogsm.patch
  wget https://raw.githubusercontent.com/shohei/IsoGSM-Docker/refs/heads/main/IsoGSM-patch/isogsm_run.patch
  chmod a+x build.sh
  ./build.sh
  cd gsm_runs
  ./configure-scr gsm
EOF
docker container start isogsm_container
docker exec -it isogsm_container /bin/bash