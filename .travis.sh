#!/usr/bin/env bash
ARGS=$@

apt-get update
apt-get install -y sudo git
sed -i.bak \
  -e 's/\(^%sudo\s*ALL=(ALL:ALL)\s*ALL\)/%sudo	ALL=(ALL:ALL) NOPASSWD: ALL/' \
  /etc/sudoers
useradd -m -G sudo travis
# Docker issue #2259
chown -R travis:travis ~travis
sudo -u travis ./X11rdp-o-matic.sh ${ARGS}
