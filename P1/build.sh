#!/bin/sh
# Build the two images used in GNS3 for P1, P2 and P3, then add them in
# GNS3: Edit > Preferences > Docker containers > New
#   - host_mochegri    (console: telnet, 2 network adapters recommended for eth0/eth1)
#   - routeur_mochegri (console: telnet, 4 network adapters for eth0-eth3)
set -e
cd "$(dirname "$0")"
docker build -t host_mochegri    -f _mochegri-1_host .
docker build -t routeur_mochegri -f _mochegri-2 .
