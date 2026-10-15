# P3 - BGP EVPN Spine-Leaf Fabric

This part implements a **spine-leaf data center fabric** using:
- **OSPF Area 0** as the underlay routing protocol for loopback reachability.
- **iBGP (AS 1)** with a **Route Reflector (RR)** on the spine and dynamic peering (`bgp listen range 1.1.1.0/29`).
- **BGP EVPN (RFC 7432 / RFC 8365)** as the control plane to distribute MAC reachability (Type 2) and VNI membership (Type 3).
- **VXLAN 10** as the data plane overlay for tenant Layer-2 traffic between hosts.

## Topology & Addressing

```text
                      _mchegri-1 (Spine / RR)
                      lo: 1.1.1.1/32  (AS 1)
             eth0 .1 /        | eth1 .5        \ eth2 .9
    10.1.1.0/30     /         | 10.1.1.4/30     \ 10.1.1.8/30
         eth0 .2   /          | eth1 .6          \ eth2 .10
      _mchegri-2          _mchegri-3          _mchegri-4
     (Leaf 1 / VTEP)     (Leaf 2 / VTEP)     (Leaf 3 / VTEP)
      lo: 1.1.1.2         lo: 1.1.1.3         lo: 1.1.1.4
         | eth1              | eth0              | eth0
   host_mchegri-1      host_mchegri-2      host_mchegri-3
    20.1.1.1/24         20.1.1.2/24         20.1.1.3/24
```

> **Interface Cabling Note:**
> Leaf-to-spine links match the subject diagram:
> - `_mchegri-2`: `eth0` -> spine `eth0`, `eth1` -> `host_mchegri-1`.
> - `_mchegri-3`: `eth1` -> spine `eth1`, `eth0` -> `host_mchegri-2`.
> - `_mchegri-4`: `eth2` -> spine `eth2`, `eth0` -> `host_mchegri-3`.
> Host scripts automatically adapt to `eth1` or `eth0`.

## Architecture Layers

| Layer | Protocol / Feature | Components | Purpose |
| :--- | :--- | :--- | :--- |
| **Underlay** | OSPFv2 Area 0 | All 4 routers | Advertises loopbacks `1.1.1.1`-`1.1.1.4` and point-to-point links. |
| **Control Plane** | iBGP EVPN (AFI 25 / SAFI 70) | Spine (RR) + Leaves | Advertises VNI and MAC reachability via BGP NLRI without data-plane flooding. |
| **Overlay** | VXLAN (VNI 10, port 4789) | Leaves (`vxlan10` + `br0`) | Encapsulates tenant L2 Ethernet frames into UDP packets routed over the underlay. |

## EVPN Route Types

- **Type 3 (IMET - Inclusive Multicast Ethernet Tag Route)**:
  - Format: `[3]:[0]:[32]:[VTEP-IP]`
  - Advertised automatically on leaf startup when `advertise-all-vni` is enabled.
  - Informs remote VTEPs where to send BUM traffic using head-end (ingress) replication.
- **Type 2 (MAC / IP Advertisement Route)**:
  - Format: `[2]:[0]:[48]:[MAC]`
  - Triggered when a local host becomes active: local bridge `br0` learns the MAC, notifies Zebra, and BGP advertises the route.
  - The RR reflects this route to other leaves, which install it into their kernel FDB with flag `extern_learn`.

## Step-by-Step Testing & Verification

### Step 1: Start Routers & Apply Configs
Run `_mchegri-1` to `_mchegri-4` in their respective consoles.

Wait ~30 seconds for OSPF and BGP to converge:
```sh
# 1. On any leaf (e.g. _mchegri-4): verify all loopbacks learned via OSPF
vtysh -c 'show ip route'
# Output should show O>* 1.1.1.1/32, 1.1.1.2/32, 1.1.1.3/32 via 10.1.1.9, eth2

# 2. On Spine (_mchegri-1): verify 3 dynamic BGP EVPN leaf sessions
vtysh -c 'show bgp l2vpn evpn summary'
# Output shows 3 neighbors (1.1.1.2, 1.1.1.3, 1.1.1.4) marked with * (dynamic)

# 3. Before hosts are started: verify ONLY Type 3 routes exist
vtysh -c 'show bgp l2vpn evpn'
# Only [3]:[0]:[32]:[1.1.1.X] routes are visible
```

### Step 2: Start Hosts & Observe Type 2 Routes
Run `_mchegri-1_host` on Host 1:
```sh
# On Leaf 1 (_mchegri-2) and Leaf 3 (_mchegri-4):
vtysh -c 'show bgp l2vpn evpn'
# A new [2]:[0]:[48]:[<host1-mac>] route appears!
```

Run `_mchegri-2_host` on Host 2 and `_mchegri-3_host` on Host 3.

### Step 3: End-to-End Connectivity
From Host 1 (`host_mchegri-1`):
```sh
ping -c 3 20.1.1.2
ping -c 3 20.1.1.3
```

On Leaf routers, check the kernel forwarding database:
```sh
bridge fdb show dev vxlan10
# Shows remote MACs with 'extern_learn' (installed by BGP EVPN) and VTEP destination IP
```

## Wireshark Packet Inspection

Capture on any spine link (e.g. `_mchegri-1` `eth0`):
- Filter: `icmp or ospf or bgp or vxlan`
- Underlay traffic: OSPF Hellos to `224.0.0.5`, BGP TCP sessions on port `179`.
- Overlay traffic: VXLAN packets (UDP `4789`, VNI `10`) carrying inner ICMP echo requests between `20.1.1.1` and `20.1.1.2`/`20.1.1.3`.

## Portable Project Export

Subject requirement:
> Export: **File > Export portable project**, check **Include base images**, save as `P3/P3.gns3project`.

