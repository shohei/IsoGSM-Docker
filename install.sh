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

if [ ! -d "IsoGSM" ]; then
    svn co svn://210.106.80.235/GRSM/IsoGSM --username guest --password guest123
else
    echo "IsoGSM directory already exists, skipping checkout."
fi
# --- docker login ---
echo "Logging in to Docker Hub (required to pull the image):"
docker login || { echo "Error: Docker login failed. Please run 'docker login' manually."; exit 1; }

docker pull shohei/isogsm:latest
docker container stop isogsm
docker container rm isogsm
docker run -i -v "`pwd`/IsoGSM:/data/IsoGSM" --name isogsm shohei/isogsm:latest << 'EOF'
  set -e
  cd /data/IsoGSM
  BASE_URL=https://raw.githubusercontent.com/shohei/IsoGSM-Docker/refs/heads/main/IsoGSM-patch
  wget -O build.sh "$BASE_URL/build.sh"
  mkdir -p pbs nopbs smallshm largeshm
  wget -O pbs/isogsm.patch          "$BASE_URL/pbs/isogsm.patch"
  wget -O nopbs/isogsm.patch        "$BASE_URL/nopbs/isogsm.patch"
  wget -O smallshm/isogsm_run.patch "$BASE_URL/smallshm/isogsm_run.patch"
  wget -O largeshm/isogsm_run.patch "$BASE_URL/largeshm/isogsm_run.patch"
  chmod a+x build.sh
  ./build.sh
EOF
docker container start isogsm
echo "****************************************************************"
echo ""
echo "IsoGSM installation complete."
echo "The next step is to run the container and execute the script in gsm_runs."
echo "To access the container and run the script, use the following command:"
echo ""
echo "$ docker exec -it isogsm /bin/bash"
echo "# cd IsoGSM/gsm_runs && ./gsm"
echo ""
echo "****************************************************************"
echo ""