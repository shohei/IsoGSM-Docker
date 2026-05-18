#!/bin/bash
#
# install.sh - IsoGSM-Docker one-liner installer
#
# Author : Shohei Aoki
# License: MIT
#

sudo apt install subversion wget
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