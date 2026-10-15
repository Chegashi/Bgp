# P2 - VXLAN

```text
host_mchegri-1 --eth1-- routeur_mchegri-1 --eth0-- Switch_mchegri --eth0-- routeur_mchegri-2 --eth1-- host_mchegri-2
  30.1.1.1/24                10.1.1.1/24                                       10.1.1.2/24              30.1.1.2/24
```

On each router `vxlan10` (VNI 10, UDP 4789) and `eth1` are put in the bridge `br0`, so the two hosts are on the same L2 network.

- `_mchegri-X_s`: static, the other router is given with `remote`.
- `_mchegri-X_g`: multicast, both routers join group 239.1.1.1 on eth0 and send broadcast/unknown frames to it.
- `_mchegri-X_host`: host IP.

## Test

Run the router script (`_s` or `_g`) on each router, the `_host` script on each host, then from host 1:

```sh
ping 30.1.1.2
```

On the routers:

```sh
ip -d link show vxlan10     # vxlan id 10 remote 10.1.1.2 ... / group 239.1.1.1
brctl showmacs br0          # MAC table
bridge fdb show dev vxlan10 # remote MAC -> VTEP IP
```

Wireshark on a switch link shows UDP 4789, VNI 10, and the ARP/ICMP of the hosts inside. In `_g` mode the first ARP request goes to 239.1.1.1, the rest is unicast.
