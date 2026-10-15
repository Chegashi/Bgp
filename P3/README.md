# P3 - BGP EVPN

```text
                      _mchegri-1 (spine, RR)  lo 1.1.1.1
              eth0 .1 /        | eth1 .5        \ eth2 .9
     10.1.1.0/30     /         | 10.1.1.4/30     \ 10.1.1.8/30
          eth0 .2   /          | eth1 .6          \ eth2 .10
       _mchegri-2          _mchegri-3          _mchegri-4
       lo 1.1.1.2          lo 1.1.1.3          lo 1.1.1.4
          | eth1              | eth0              | eth0
    host_mchegri-1      host_mchegri-2      host_mchegri-3
     20.1.1.1/24         20.1.1.2/24         20.1.1.3/24
```

- Underlay: OSPF area 0, every router reaches the loopbacks.
- BGP: AS 1, sessions between loopbacks (`update-source lo`). The spine is route reflector and accepts the leaves dynamically (`bgp listen range 1.1.1.0/29`), so no leaf is declared on it.
- Leaves: `vxlan10` (VNI 10, `local 1.1.1.X`, `nolearning`) in `br0` with the host port, and `advertise-all-vni` in the `l2vpn evpn` family. Remote MACs come from BGP only.

## Test

Run `_mchegri-1` to `_mchegri-4` on the routers. After OSPF and BGP are up (can take a minute or two):

```sh
vtysh -c 'show ip route'                  # on _mchegri-4: 1.1.1.1-3 learned by OSPF
vtysh -c 'show bgp l2vpn evpn summary'    # on the RR: 3 dynamic neighbors (*)
vtysh -c 'show bgp l2vpn evpn'            # only type 3 routes, one per VTEP
```

Then run the `_host` scripts. Each host MAC shows up as a type 2 route on its leaf and, through the RR, on the other leaves. From host 1:

```sh
ping 20.1.1.2
ping 20.1.1.3
```

`bridge fdb show dev vxlan10` on a leaf shows the remote MACs with the VTEP IP (`extern_learn` = added by BGP) and one `00:00:00:00:00:00` entry per remote VTEP for broadcast.
