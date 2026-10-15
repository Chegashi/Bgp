# P1 - GNS3 with docker

Two images:

- `_mchegri-1_host`: Alpine + busybox, iproute2, net-tools, iputils.
- `_mchegri-2`: FRRouting 9.1.3 (Alpine based). bgpd, ospfd and isisd are switched on in `/etc/frr/daemons`, zebra always runs. tcpdump added for debugging.

No IP address is set in either image.

## Build

```sh
sh build.sh
```

Tags: `host_mchegri` and `routeur_mchegri` (the same images are used in P2 and P3).

## GNS3

Topology: `host_mchegri-1 eth0 <-> eth0 routeur_mchegri`.

Check on the router console:

```sh
vtysh -c 'show daemons'    # zebra bgpd ospfd isisd ...
ip addr                    # only 127.0.0.1
```

Export: File > Export portable project, with base images, as `P1.gns3project`.
