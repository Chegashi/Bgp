# BADASS

BGP At Doors of Autonomous Systems is Simple - 42 network project.

Three small networks built in GNS3 with docker containers:

- **P1**: the two docker images (a host and a router running FRRouting).
- **P2**: two hosts on the same VXLAN (VNI 10), first with a static peer, then with a multicast group.
- **P3**: a small spine/leaf data center. OSPF underlay, iBGP with a route reflector, EVPN to share the MAC addresses between the VTEPs.

Login used in device names: `mchegri`.

## Layout

```text
P1/  Dockerfiles of the host and router images, build.sh
P2/  config scripts for the routers (_s static, _g multicast) and hosts
P3/  config scripts for the spine (_mchegri-1), the leaves (_mchegri-2/3/4) and hosts
MANUAL.md  my notes: protocols, commands, troubleshooting, defense questions
```

Every file in P2/P3 is a shell script to run inside the device with the same name.

## Build the images

```sh
sh P1/build.sh
```

This gives `host_mchegri` and `routeur_mchegri`. In GNS3: Edit > Preferences > Docker containers > New, console type telnet, 4 adapters for the router.

## Addressing

|    | Underlay | Hosts |
| -- | -- | -- |
| P2 | 10.1.1.1/24, 10.1.1.2/24 | 30.1.1.1/24, 30.1.1.2/24 |
| P3 | loopbacks 1.1.1.1-4/32, links 10.1.1.0/30, .4/30, .8/30 | 20.1.1.1-3/24 |

VXLAN: VNI 10, interface `vxlan10`, bridge `br0`, UDP 4789. P2 multicast group: 239.1.1.1. P3: AS 1, spine = route reflector, leaves accepted with `bgp listen range 1.1.1.0/29`.

## Useful commands

```sh
vtysh -c 'show ip ospf neighbor'
vtysh -c 'show bgp l2vpn evpn summary'
vtysh -c 'show bgp l2vpn evpn'          # type 3 routes, then type 2 when hosts are up
ip -d link show vxlan10
bridge fdb show dev vxlan10
brctl showmacs br0
```

## References

- RFC 7348 (VXLAN), RFC 7432 (EVPN), RFC 8365 (EVPN with VXLAN), RFC 4271 (BGP), RFC 4760 (MP-BGP), RFC 4456 (route reflection), RFC 2328 (OSPF)
- FRRouting docs: <https://docs.frrouting.org/>
- <https://vincent.bernat.ch/en/blog/2017-vxlan-linux> and <https://vincent.bernat.ch/en/blog/2017-vxlan-bgp-evpn>
