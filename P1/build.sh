#!/bin/sh
# Build the two images used in GNS3 for P1, P2 and P3, then add them in
# GNS3: Edit > Preferences > Docker containers > New
#   - host_mchegri    (console: telnet)
#   - routeur_mchegri (console: telnet, 4 network adapters)
set -e
cd "$(dirname "$0")"
docker build -t host_mchegri    -f _mchegri-1_host .
docker build -t routeur_mchegri -f _mchegri-2 .
