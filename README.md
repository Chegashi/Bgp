# BADASS: BGP At Doors of Autonomous Systems is Simple

A comprehensive implementation and theoretical guide for the **42 Network BADASS** project. This project explores modern data center network architecture by building simulated network topologies in **GNS3** with **Docker** containers, progressing from basic image creation to **VXLAN** tunneling and **BGP EVPN** control-plane fabric automation.

Login used across all devices, scripts, and images: **`mchegri`**.

---

## Table of Contents

- [1. Executive Overview \& Architecture](#1-executive-overview--architecture)
  - [1.1 The Problem: Why Traditional VLANs Fail at Scale](#11-the-problem-why-traditional-vlans-fail-at-scale)
  - [1.2 The Solution: Overlay / Underlay Network Architecture](#12-the-solution-overlay--underlay-network-architecture)
  - [1.3 Project Progression: P1, P2, and P3](#13-project-progression-p1-p2-and-p3)
  - [1.4 Repository Structure](#14-repository-structure)
  - [1.5 Addressing \& Network Summary](#15-addressing--network-summary)
- [2. Theoretical Foundations \& Protocols](#2-theoretical-foundations--protocols)
  - [2.1 OSI Stack \& Encapsulation Overhead](#21-osi-stack--encapsulation-overhead)
  - [2.2 OSPFv2 (Open Shortest Path First)](#22-ospfv2-open-shortest-path-first)
  - [2.3 BGP-4 \& Multiprotocol BGP (MP-BGP)](#23-bgp-4--multiprotocol-bgp-mp-bgp)
  - [2.4 BGP EVPN (RFC 7432 / RFC 8365)](#24-bgp-evpn-rfc-7432--rfc-8365)
  - [2.5 Route Reflection (RFC 4456) \& Dynamic Listen Peering](#25-route-reflection-rfc-4456--dynamic-listen-peering)
  - [2.6 IS-IS (Intermediate System to Intermediate System)](#26-is-is-intermediate-system-to-intermediate-system)
- [3. Part 1: Base Docker Images \& GNS3 Integration](#3-part-1-base-docker-images--gns3-integration)
  - [3.1 Host Image: `_mchegri-1_host`](#31-host-image-_mchegri-1_host)
  - [3.2 Router Image: `_mchegri-2`](#32-router-image-_mchegri-2)
  - [3.3 Build Automation: `build.sh`](#33-build-automation-buildsh)
  - [3.4 GNS3 Verification](#34-gns3-verification)
- [4. Part 2: Discovering VXLAN (Static \& Multicast)](#4-part-2-discovering-vxlan-static--multicast)
  - [4.1 Topology \& Addressing](#41-topology--addressing)
  - [4.2 Linux Network Primitives (`vxlan10` \& `br0`)](#42-linux-network-primitives-vxlan10--br0)
  - [4.3 Static Unicast Mode (`_s`)](#43-static-unicast-mode-_s)
  - [4.4 Dynamic Multicast Mode (`_g`)](#44-dynamic-multicast-mode-_g)
  - [4.5 Host Configuration \& Resilient Interface Detection](#45-host-configuration--resilient-interface-detection)
  - [4.6 Packet Walkthrough: How VXLAN Forwards Traffic](#46-packet-walkthrough-how-vxlan-forwards-traffic)
  - [4.7 Wireshark Capture Analysis](#47-wireshark-capture-analysis)
- [5. Part 3: Clos Spine-Leaf Fabric with BGP EVPN](#5-part-3-clos-spine-leaf-fabric-with-bgp-evpn)
  - [5.1 Clos Spine-Leaf Architecture \& Interface Mapping](#51-clos-spine-leaf-architecture--interface-mapping)
  - [5.2 Spine / Route Reflector Configuration: `_mchegri-1`](#52-spine--route-reflector-configuration-_mchegri-1)
  - [5.3 Leaf / VTEP Configurations: `_mchegri-2`, `_mchegri-3`, `_mchegri-4`](#53-leaf--vtep-configurations-_mchegri-2-_mchegri-3-_mchegri-4)
  - [5.4 Host Configurations in P3](#54-host-configurations-in-p3)
  - [5.5 EVPN Route Lifecycle (Type 3 vs Type 2)](#55-evpn-route-lifecycle-type-3-vs-type-2)
  - [5.6 End-to-End Packet Walk: Host 1 to Host 2 Across the Fabric](#56-end-to-end-packet-walk-host-1-to-host-2-across-the-fabric)
  - [5.7 Wireshark Capture Verification](#57-wireshark-capture-verification)
- [6. Step-by-Step GNS3 Setup Guide](#6-step-by-step-gns3-setup-guide)
  - [6.1 Creating Docker Templates](#61-creating-docker-templates)
  - [6.2 Building Topologies \& Cabling Rules](#62-building-topologies--cabling-rules)
  - [6.3 Applying Configurations](#63-applying-configurations)
  - [6.4 Exporting Portable Projects (`.gns3project`)](#64-exporting-portable-projects-gns3project)
- [7. Master Diagnostic \& Command Cheat Sheet](#7-master-diagnostic--command-cheat-sheet)
  - [7.1 Linux Network Commands (`ip`, `bridge`, `brctl`)](#71-linux-network-commands-ip-bridge-brctl)
  - [7.2 FRRouting `vtysh` Commands](#72-frrouting-vtysh-commands)
  - [7.3 Packet Capture \& Wireshark Display Filters](#73-packet-capture--wireshark-display-filters)
- [8. Comprehensive Troubleshooting Matrix](#8-comprehensive-troubleshooting-matrix)
- [9. Peer-Evaluation Defense Guide](#9-peer-evaluation-defense-guide)
  - [9.1 Step-by-Step Live Demonstration Workflow](#91-step-by-step-live-demonstration-workflow)
  - [9.2 Theoretical Questions \& Model Answers](#92-theoretical-questions--model-answers)
- [10. References \& RFCs](#10-references--rfcs)

---

## 1. Executive Overview & Architecture

### 1.1 The Problem: Why Traditional VLANs Fail at Scale

In multi-tenant data centers, cloud infrastructure hosts millions of virtual instances and containers belonging to different organizations. Each tenant requires isolation at Layer 2 (L2) so that their workloads can share the same subnet and broadcast domain regardless of physical server location.

Traditional enterprise networking relies on IEEE 802.1Q **VLANs** (Virtual Local Area Networks) and **Spanning Tree Protocol (STP)**. At cloud scale, this model collapses due to three major limitations:

1. **12-bit ID Limit**: A VLAN tag has only 12 bits, restricting the entire physical infrastructure to a maximum of $2^{12} - 2 = 4,094$ usable broadcast domains. Modern clouds serve tens of thousands of tenants simultaneously.
2. **Spanning Tree Protocol (STP) Waste**: To prevent loops in an L2 topology, STP blocks redundant physical links. In a dual-uplink switch topology, 50% of the purchased network bandwidth sits idle.
3. **Uncontrolled Broadcast Flooding**: Layer 2 broadcast traffic (e.g., ARP resolution) floods every switch port participating in the VLAN, consuming bandwidth and CPU across all compute nodes.

```
Traditional L2 Network (Spanning Tree blocks redundant links)
   [Switch A] ═════ (Blocked by STP) ═════ [Switch B]
        \                                      /
         \                                    /
          ─────── [Access Switch / Host] ────
```

### 1.2 The Solution: Overlay / Underlay Network Architecture

Modern data center networks decouple the physical topology from the virtual network using an **Underlay / Overlay** architecture:

```
┌─────────────────────────────────────────────────────────────┐
│ OVERLAY: Layer 2 Tenant Broadcast Domains (VXLAN VNI 10)     │
│ Host 1 (30.1.1.1) <─────────────────────> Host 2 (30.1.1.2) │
└───────────────────────────▲─────────────────────────────────┘
                            │ Encapsulated in UDP 4789
┌───────────────────────────▼─────────────────────────────────┐
│ UNDERLAY: Layer 3 Routed IP Fabric (OSPFv2 / ECMP)          │
│ Leaf 1 (1.1.1.2) <──────> Spine (1.1.1.1) <──────> Leaf 2   │
└─────────────────────────────────────────────────────────────┘
```

1. **Underlay Network (Layer 3)**: A resilient, highly scalable routed IP network. All links forward traffic simultaneously using Equal-Cost Multi-Path (**ECMP**) routing via protocols like **OSPF** or eBGP. No ports are blocked.
2. **Overlay Network (Layer 2 over Layer 3)**: Tenant Ethernet frames are encapsulated within standard IP/UDP packets across the underlay using **VXLAN** (Virtual eXtensible LAN).
3. **Control Plane (BGP EVPN)**: Instead of flooding unknown frames to learn MAC addresses dynamically in the data plane (flood-and-learn), routers exchange MAC reachability information upfront via **BGP EVPN** (Ethernet VPN).

### 1.3 Project Progression: P1, P2, and P3

- **Part 1 (P1)**: Construction of two minimal, compliant base Docker images: a generic Linux host container and a routing engine container running **FRRouting** with `zebra`, `bgpd`, `ospfd`, and `isisd`.
- **Part 2 (P2)**: Establishing an L2 overlay across a routed L3 underlay using VXLAN (VNI 10) and a software bridge (`br0`). Evaluated first in **static unicast mode**, then in **dynamic multicast mode** (`239.1.1.1`).
- **Part 3 (P3)**: Building a carrier-grade data center **Clos spine-leaf fabric** with 1 Route Reflector spine, 3 VTEP leaves, and 3 hosts. The underlay routes traffic with OSPF Area 0, while iBGP EVPN dynamically exchanges MAC reachability with zero flood-and-learn.

### 1.4 Repository Structure

```text
bgp/
├── README.md               # Master technical manual, step-by-step guide & defense notes
├── MANUAL.md               # Secondary reference pointer
├── en.subject.pdf          # Official 42 project specification
├── P1/
│   ├── _mchegri-1_host     # Dockerfile: Host image (Alpine + BusyBox + iproute2 + ping)
│   ├── _mchegri-2          # Dockerfile: Router image (FRRouting 9.1.3 + daemons + tcpdump)
│   ├── build.sh            # Build script tagging host_mchegri and routeur_mchegri
│   └── README.md           # P1 specific instructions and verification steps
├── P2/
│   ├── _mchegri-1_s        # Router 1: VXLAN static unicast configuration script
│   ├── _mchegri-2_s        # Router 2: VXLAN static unicast configuration script
│   ├── _mchegri-1_g        # Router 1: VXLAN multicast group configuration script
│   ├── _mchegri-2_g        # Router 2: VXLAN multicast group configuration script
│   ├── _mchegri-1_host     # Host 1: IP configuration script (30.1.1.1/24)
│   ├── _mchegri-2_host     # Host 2: IP configuration script (30.1.1.2/24)
│   └── README.md           # P2 specific instructions and Wireshark filter guide
└── P3/
    ├── _mchegri-1          # Spine Router: OSPF Area 0 + BGP Route Reflector for EVPN
    ├── _mchegri-2          # Leaf 1 Router: VTEP (lo: 1.1.1.2) + OSPF + iBGP EVPN
    ├── _mchegri-3          # Leaf 2 Router: VTEP (lo: 1.1.1.3) + OSPF + iBGP EVPN
    ├── _mchegri-4          # Leaf 3 Router: VTEP (lo: 1.1.1.4) + OSPF + iBGP EVPN
    ├── _mchegri-1_host     # Host 1: IP configuration script (20.1.1.1/24)
    ├── _mchegri-2_host     # Host 2: IP configuration script (20.1.1.2/24)
    ├── _mchegri-3_host     # Host 3: IP configuration script (20.1.1.3/24)
    └── README.md           # P3 specific instructions, route lifecycle & packet walks
```

### 1.5 Addressing & Network Summary

| Parameter | Part 2 (VXLAN Discovery) | Part 3 (BGP EVPN Fabric) |
| :--- | :--- | :--- |
| **Underlay Subnets** | `10.1.1.0/24` (`10.1.1.1`, `10.1.1.2`) | Point-to-point `/30` links (`10.1.1.0/30`, `.4/30`, `.8/30`) |
| **Router Loopbacks** | None (interface IPs directly used) | `1.1.1.1/32` (Spine), `1.1.1.2-4/32` (Leaves) |
| **Overlay Hosts** | `30.1.1.1/24`, `30.1.1.2/24` | `20.1.1.1/24`, `20.1.1.2/24`, `20.1.1.3/24` |
| **VXLAN Network ID** | VNI `10` | VNI `10` |
| **UDP Port** | Standard IANA `4789` | Standard IANA `4789` |
| **Linux Interface** | `vxlan10` enslaved to bridge `br0` | `vxlan10` enslaved to bridge `br0` (`nolearning`) |
| **Control Plane** | None (Static unicast peer or Multicast `239.1.1.1`) | **iBGP EVPN** (AS 1, Route Reflector spine) |
| **Underlay Routing** | Static routing / direct connected | **OSPFv2 Area 0** |

---

## 2. Theoretical Foundations & Protocols

### 2.1 OSI Stack & Encapsulation Overhead

VXLAN encapsulates Layer 2 Ethernet frames inside Layer 4 UDP datagrams:

```text
┌─────────────────┬─────────────────────────────────────────────────────────┐
│ Outer Ethernet  │ Dest MAC (Next Hop), Src MAC, EtherType: 0x0800 (IPv4)  │ 14 bytes
├─────────────────┼─────────────────────────────────────────────────────────┤
│ Outer IP        │ Src IP (VTEP 1), Dest IP (VTEP 2), Protocol: 17 (UDP)   │ 20 bytes
├─────────────────┼─────────────────────────────────────────────────────────┤
│ Outer UDP       │ Src Port (Hash of inner flow), Dest Port: 4789 (VXLAN)  │  8 bytes
├─────────────────┼─────────────────────────────────────────────────────────┤
│ VXLAN Header    │ Flags (0x08 = VNI Valid), 24-bit VNI: 10, Reserved      │  8 bytes
├─────────────────┼─────────────────────────────────────────────────────────┤
│ Inner Ethernet  │ Dest MAC (Target Host), Src MAC (Source Host)           │ 14 bytes
├─────────────────┼─────────────────────────────────────────────────────────┤
│ Inner Payload   │ Tenant IP Packet (ICMP, TCP, UDP) or ARP Request/Reply  │ variable
└─────────────────┴─────────────────────────────────────────────────────────┘
```

- **Encapsulation Overhead**: $14 + 20 + 8 + 8 = 50$ bytes.
- **MTU Implication**: Standard Ethernet MTU is 1500 bytes. To avoid fragmentation across a physical data center underlay, physical switch interfaces must support **Jumbo Frames** (typically MTU $\ge 1550$ bytes, commonly 9000 or 9216 bytes). Inside GNS3 Docker containers, Linux handles this transparently in software.

### 2.2 OSPFv2 (Open Shortest Path First)

OSPF ([RFC 2328](https://datatracker.ietf.org/doc/html/rfc2328)) is an interior link-state routing protocol operating inside an Autonomous System:
- **Operation**: Routers exchange Link-State Advertisements (**LSAs**) to build an identical map (Link-State Database / LSDB) of the network topology. Every router then independently computes the shortest path tree using Dijkstra's algorithm.
- **Area 0 (Backbone)**: All OSPF areas must connect to the central backbone area. In Part 3, the entire underlay fabric resides in Area 0.
- **Multicast Transport**: OSPF routers discover neighbors by sending Hello packets to IPv4 multicast address `224.0.0.5` (`AllSPFRouters`) on IP protocol 89.
- **Purpose in P3**: Provides loopback-to-loopback reachability (`1.1.1.1/32` through `1.1.1.4/32`) so that iBGP TCP sessions and VXLAN UDP tunnels can establish reliably across any physical path.

### 2.3 BGP-4 & Multiprotocol BGP (MP-BGP)

Border Gateway Protocol ([RFC 4271](https://datatracker.ietf.org/doc/html/rfc4271)) is a path-vector routing protocol running over reliable TCP on port **179**.
- **iBGP vs eBGP**: BGP sessions between routers in the same Autonomous System (AS) are **Internal BGP (iBGP)**. Sessions between different ASes are **External BGP (eBGP)**.
- **Split-Horizon Rule**: To prevent routing loops within an AS, a standard iBGP router will **never** re-advertise a route learned from an iBGP peer to another iBGP peer. Consequently, traditional iBGP requires a full mesh ($N \times (N - 1) / 2$ sessions).
- **MP-BGP Extensions ([RFC 4760](https://datatracker.ietf.org/doc/html/rfc4760))**: Extends BGP using Address Family Identifiers (AFI) and Subsequent AFIs (SAFI) to carry routing information (NLRI) for non-IPv4 protocols, such as IPv6, VPNv4, and **L2VPN EVPN** (AFI 25, SAFI 70).

### 2.4 BGP EVPN (RFC 7432 / RFC 8365)

Ethernet VPN (EVPN) transforms BGP into a unified control plane for Layer 2 and Layer 3 overlays. In our architecture, the VTEPs publish routes into BGP instead of relying on data-plane flooding:

```text
+--------------------------------------------------------------------------+
| EVPN Route Type 3: Inclusive Multicast Ethernet Tag (IMET) Route        |
| - Advertised at startup by each VTEP                                     |
| - Content: VNI (10), Originating Router IP (Loopback)                    |
| - Purpose: Tells all leaves who belongs to VNI 10 for BUM replication    |
+--------------------------------------------------------------------------+
                                     │
+--------------------------------------------------------------------------+
| EVPN Route Type 2: MAC / IP Advertisement Route                         |
| - Advertised dynamically when a local host transmits                     |
| - Content: Host MAC, Host IP (optional), VNI (10), Next-Hop (VTEP IP)    |
| - Purpose: Installs remote MAC -> VTEP mapping in remote leaf FDB        |
+--------------------------------------------------------------------------+
```

### 2.5 Route Reflection (RFC 4456) & Dynamic Listen Peering

To eliminate the need for an $O(N^2)$ iBGP full mesh between leaves, the spine router acts as a **Route Reflector (RR)** ([RFC 4456](https://datatracker.ietf.org/doc/html/rfc4456)):
- The spine marks all leaves as `route-reflector-client`.
- When Leaf 1 advertises an EVPN route to the RR, the RR re-advertises ("reflects") that route to Leaf 2 and Leaf 3, safely bypassing the iBGP split-horizon rule.
- **Dynamic Neighbors**: Rather than configuring every leaf IP manually on the spine, FRR provides `bgp listen range 1.1.1.0/29 peer-group ibgp`. Any leaf initiating a BGP connection with a loopback inside `1.1.1.0/29` (`1.1.1.1` to `1.1.1.6`) is automatically accepted into the peer group.

### 2.6 IS-IS (Intermediate System to Intermediate System)

IS-IS ([RFC 1195](https://datatracker.ietf.org/doc/html/rfc1195)) is a link-state interior routing protocol designed by ISO that operates directly on Layer 2 (data-link frames), bypassing the IP stack entirely.
- **Requirement in P1**: The subject requires `isisd` to be active and configured in the router image along with `zebra`, `bgpd`, and `ospfd`. In modern ISP and data center networks, IS-IS is widely utilized as an alternative to OSPF.

---

## 3. Part 1: Base Docker Images & GNS3 Integration

Part 1 requires creating two custom Docker images that serve as generic building blocks throughout P1, P2, and P3.

### 3.1 Host Image: `_mchegri-1_host`

File: [P1/_mchegri-1_host](file:///Users/mohamedchegri/Desktop/edu/1337/bgp/P1/_mchegri-1_host)

```dockerfile
# Use Alpine Linux as a minimal, lightweight base
FROM alpine:3

# Install busybox and essential networking tools (iproute2 for 'ip', iputils for 'ping', net-tools for 'ifconfig')
RUN apk update && apk add --no-cache \
    busybox \
    iproute2 \
    net-tools \
    iputils
```

- **Base**: `alpine:3` provides a minimal, secure, 5 MB image.
- **Utilities**: `iproute2` installs modern `ip` commands, `net-tools` provides legacy tools (`ifconfig`, `arp`), and `iputils` provides full-featured `ping`.
- **Subject Constraint**: No IP address is configured inside the image.

### 3.2 Router Image: `_mchegri-2`

File: [P1/_mchegri-2](file:///Users/mohamedchegri/Desktop/edu/1337/bgp/P1/_mchegri-2)

```dockerfile
# Router image: FRRouting (maintained fork of quagga) on Alpine Linux.
# zebra manages the kernel routing table; bgpd, ospfd and isisd run on top of it.
# The official image already ships busybox, iproute2 and bridge-utils (brctl).
FROM quay.io/frrouting/frr:9.1.3

# tcpdump: to inspect VXLAN / OSPF / BGP traffic from the router itself
RUN apk add --no-cache tcpdump

# Enable the routing daemons required by the subject (zebra is always started):
# - bgpd:  Border Gateway Protocol (P3: iBGP EVPN)
# - ospfd: Open Shortest Path First (P3: underlay)
# - isisd: IS-IS routing engine
RUN sed -i -e 's/^bgpd=no/bgpd=yes/' \
           -e 's/^ospfd=no/ospfd=yes/' \
           -e 's/^isisd=no/isisd=yes/' /etc/frr/daemons \
 && touch /etc/frr/vtysh.conf

# No IP address is configured by default.
# The inherited entrypoint (/sbin/tini -- /usr/lib/frr/docker-start) keeps
# watchfrr in the foreground, which starts and supervises zebra + the daemons,
# so the container stays alive in GNS3.
```

- **Base**: `quay.io/frrouting/frr:9.1.3` is the official upstream release.
- **Daemons**: Modifying `/etc/frr/daemons` instructs `watchfrr` to launch `zebra`, `bgpd`, `ospfd`, and `isisd` concurrently on container boot.
- **Diagnostics**: `tcpdump` is installed so network packets can be inspected directly inside router consoles.
- **Subject Constraint**: No default IP addresses are configured.

### 3.3 Build Automation: `build.sh`

File: [P1/build.sh](file:///Users/mohamedchegri/Desktop/edu/1337/bgp/P1/build.sh)

```sh
#!/bin/sh
# Build the two images used in GNS3 for P1, P2 and P3, then add them in
# GNS3: Edit > Preferences > Docker containers > New
#   - host_mchegri    (console: telnet, 2 network adapters recommended for eth0/eth1)
#   - routeur_mchegri (console: telnet, 4 network adapters for eth0-eth3)
set -e
cd "$(dirname "$0")"
docker build -t host_mchegri    -f _mchegri-1_host .
docker build -t routeur_mchegri -f _mchegri-2 .
```

Run this script inside your VM terminal:
```sh
sh P1/build.sh
```

### 3.4 GNS3 Verification

Connect `host_mchegri-1` to `routeur_mchegri` in GNS3. Open the router terminal and run:

```sh
# 1. Verify all required daemons are running
vtysh -c 'show daemons'
# Expected output: mgmtd zebra ospfd bgpd isisd watchfrr staticd

# 2. Verify no IP addresses exist on ethernet interfaces
ip addr
# Expected output: only 127.0.0.1 on loopback; eth0 is unconfigured
```

---

## 4. Part 2: Discovering VXLAN (Static & Multicast)

### 4.1 Topology & Addressing

In Part 2, two hosts on subnet `30.1.1.0/24` communicate across a Layer 3 underlay (`10.1.1.0/24`) using a VXLAN tunnel (`vxlan10`) bound to a Linux bridge (`br0`).

```text
host_mchegri-1                   routeur_mchegri-1        Switch_mchegri        routeur_mchegri-2                   host_mchegri-2
┌──────────────────────┐        ┌──────────────────┐    ┌─────────────────┐    ┌──────────────────┐        ┌──────────────────────┐
│ IP: 30.1.1.1/24      │        │ br0 (eth1+vxlan) │    │  Standard GNS3  │    │ br0 (eth1+vxlan) │        │ IP: 30.1.1.2/24      │
│ Port: eth1 or eth0   ├────────┤ eth1        eth0 ├────┤ e0           e1 ├────┤ eth0        eth1 ├────────┤ Port: eth1 or eth0   │
└──────────────────────┘        └──────────────────┘    └─────────────────┘    └──────────────────┘        └──────────────────────┘
                                  Underlay: 10.1.1.1                             Underlay: 10.1.1.2
```

### 4.2 Linux Network Primitives (`vxlan10` & `br0`)

1. **`vxlan10`**: A virtual network device created by the Linux kernel driver. It takes Ethernet frames entering its port, prepends IP/UDP/VXLAN headers, and sends them out the physical interface (`eth0`). Conversely, incoming UDP 4789 packets are stripped of their outer headers and delivered as raw Ethernet frames.
2. **`br0`**: A Linux software bridge acting as a standard Layer 2 switch. By enslaving both the local host port (`eth1`) and the tunnel port (`vxlan10`) into `br0`, the bridge forwards frames between the physical host and the virtual tunnel based on destination MAC addresses.

### 4.3 Static Unicast Mode (`_s`)

Files: [P2/_mchegri-1_s](file:///Users/mohamedchegri/Desktop/edu/1337/bgp/P2/_mchegri-1_s) and [P2/_mchegri-2_s](file:///Users/mohamedchegri/Desktop/edu/1337/bgp/P2/_mchegri-2_s)

On **Router 1** (`_mchegri-1_s`):
```sh
#!/bin/sh

# Clean up existing interfaces if re-running or switching modes
ip link del dev vxlan10 2>/dev/null || true
ip link del dev br0 2>/dev/null || true

# Configure Underlay Interface
ip addr replace 10.1.1.1/24 dev eth0
ip link set dev eth0 up

# Create VXLAN interface (VNI: 10, Unicast remote to Router 2: 10.1.1.2)
ip link add name vxlan10 type vxlan id 10 dev eth0 remote 10.1.1.2 local 10.1.1.1 dstport 4789
ip link set dev vxlan10 up

# Create Bridge br0 and attach eth1 and vxlan10
ip link add name br0 type bridge
ip link set dev br0 up
ip link set dev eth1 up
ip link set dev eth1 master br0
ip link set dev vxlan10 master br0
```

- `remote 10.1.1.2 local 10.1.1.1`: Explicitly sets the single unicast VTEP peer IP.
- `dstport 4789`: Sets the standard IANA destination port (Linux defaults to non-standard 8472 unless specified).
- **Idempotency**: The initial `ip link del` commands ensure the script can be re-run cleanly without throwing `File exists` errors.

### 4.4 Dynamic Multicast Mode (`_g`)

Files: [P2/_mchegri-1_g](file:///Users/mohamedchegri/Desktop/edu/1337/bgp/P2/_mchegri-1_g) and [P2/_mchegri-2_g](file:///Users/mohamedchegri/Desktop/edu/1337/bgp/P2/_mchegri-2_g)

On **Router 1** (`_mchegri-1_g`):
```sh
#!/bin/sh

# Clean up existing interfaces if re-running or switching modes
ip link del dev vxlan10 2>/dev/null || true
ip link del dev br0 2>/dev/null || true

# Configure Underlay Interface
ip addr replace 10.1.1.1/24 dev eth0
ip link set dev eth0 up

# Create VXLAN interface (VNI: 10, Multicast Group: 239.1.1.1)
ip link add name vxlan10 type vxlan id 10 dev eth0 group 239.1.1.1 dstport 4789
ip link set dev vxlan10 up

# Create Bridge br0 and attach eth1 and vxlan10
ip link add name br0 type bridge
ip link set dev br0 up
ip link set dev eth1 up
ip link set dev eth1 master br0
ip link set dev vxlan10 master br0
```

- `group 239.1.1.1`: The router joins the multicast group on `eth0` via IGMP. Broadcast and unknown unicast frames are flooded only to nodes subscribed to `239.1.1.1`.
- When Router 2 replies with unicast traffic, Router 1 records Router 2's MAC in its Forwarding Database (FDB). Subsequent frames are unicast directly.

### 4.5 Host Configuration & Resilient Interface Detection

Files: [P2/_mchegri-1_host](file:///Users/mohamedchegri/Desktop/edu/1337/bgp/P2/_mchegri-1_host) and [P2/_mchegri-2_host](file:///Users/mohamedchegri/Desktop/edu/1337/bgp/P2/_mchegri-2_host)

```sh
#!/bin/sh

# Host 1 Configuration (P2)
# Uses eth1 if available (matching the subject diagram), falls back to eth0
IFACE="eth0"
[ -d "/sys/class/net/eth1" ] && IFACE="eth1"

ip addr replace 30.1.1.1/24 dev "$IFACE"
ip link set dev "$IFACE" up
```

> **Why Resilient Interface Detection Matters**:
> In GNS3, docker container templates default to 1 adapter (`eth0`). If an evaluator runs the project on a template with 1 adapter, hardcoding `eth1` throws `Cannot find device "eth1"`. This script auto-detects `eth1` (if cabled per the subject diagram) and falls back cleanly to `eth0`.

### 4.6 Packet Walkthrough: How VXLAN Forwards Traffic

```text
Step 1: Host 1 (30.1.1.1) pings Host 2 (30.1.1.2).
        Host 1 has no ARP entry for 30.1.1.2 -> broadcasts ARP Request.
Step 2: Router 1's bridge br0 receives the frame on eth1.
        br0 learns Host 1's MAC on port eth1.
        br0 floods the broadcast frame to all bridge ports -> enters vxlan10.
Step 3: vxlan10 encapsulates the frame into an outer UDP/IP packet:
        - Static mode: Dest IP = 10.1.1.2 (Router 2).
        - Multicast mode: Dest IP = 239.1.1.1 (Multicast group).
Step 4: Router 2 receives UDP 4789 on eth0.
        vxlan10 decapsulates the packet and extracts the inner ARP broadcast.
        Router 2 learns: Host 1 MAC is reachable via outer IP 10.1.1.1.
Step 5: Router 2 injects the frame into br0, which forwards it out eth1 to Host 2.
Step 6: Host 2 receives ARP Request and replies with unicast ARP Reply.
        Router 2 encapsulates it directly to Router 1 (10.1.1.1).
        Both routers have now learned host MACs in their bridge and FDB!
```

### 4.7 Wireshark Capture Analysis

Start Wireshark on the link between `routeur_mchegri-1` and `Switch_mchegri`:
- Filter: `udp.port == 4789` or `vxlan`
- In static mode (`_s`), you will observe outer IP packets addressed from `10.1.1.1` to `10.1.1.2`.
- In dynamic multicast mode (`_g`), you will observe the initial ARP request addressed to `239.1.1.1`, followed by unicast ICMP packets (`10.1.1.1` <-> `10.1.1.2`).
- Inspect the payload: The Wireshark packet dissector decodes `Virtual eXtensible Local Area Network (VNI: 10)` containing the inner Ethernet frame.

---

## 5. Part 3: Clos Spine-Leaf Fabric with BGP EVPN

### 5.1 Clos Spine-Leaf Architecture & Interface Mapping

Part 3 implements a modern two-tier Clos data center fabric:

```text
                              ┌─────────────────────────────┐
                              │ _mchegri-1  SPINE / RR      │
                              │ lo: 1.1.1.1/32  (AS 1)      │
                              │ eth0 .1  eth1 .5  eth2 .9   │
                              └──┬──────────┬──────────┬────┘
                    10.1.1.0/30  │  10.1.1.4/30        │  10.1.1.8/30
                     eth0 .2     │   eth1 .6           │   eth2 .10
          ┌────────────────────┐ │ ┌────────────────────┐ ┌────────────────────┐
          │ _mchegri-2 LEAF 1  ├─┘ │ _mchegri-3 LEAF 2  │ │ _mchegri-4 LEAF 3  │
          │ lo: 1.1.1.2/32     │   │ lo: 1.1.1.3/32     │ │ lo: 1.1.1.4/32     │
          │ br0 = eth1+vxlan10 │   │ br0 = eth0+vxlan10 │ │ br0 = eth0+vxlan10 │
          └─────────┬──────────┘   └─────────┬──────────┘ └─────────┬──────────┘
                  eth1                      eth0                   eth0
          host_mchegri-1             host_mchegri-2          host_mchegri-3
           20.1.1.1/24                20.1.1.2/24             20.1.1.3/24
```

#### Precise Port Cabling Mapping

To match the official subject diagrams precisely, wire the devices as follows:

| Device | Node Name | Interface | Connected To Device | Remote Port | Subnet / Role |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Spine** | `_mchegri-1` | `eth0` | `_mchegri-2` (Leaf 1) | `eth0` | `10.1.1.0/30` (`.1` / `.2`) |
| **Spine** | `_mchegri-1` | `eth1` | `_mchegri-3` (Leaf 2) | `eth1` | `10.1.1.4/30` (`.5` / `.6`) |
| **Spine** | `_mchegri-1` | `eth2` | `_mchegri-4` (Leaf 3) | `eth2` | `10.1.1.8/30` (`.9` / `.10`) |
| **Leaf 1** | `_mchegri-2` | `eth1` | `host_mchegri-1` | `eth1` (or `eth0`) | Bridge `br0` (Overlay `20.1.1.1`) |
| **Leaf 2** | `_mchegri-3` | `eth0` | `host_mchegri-2` | `eth0` | Bridge `br0` (Overlay `20.1.1.2`) |
| **Leaf 3** | `_mchegri-4` | `eth0` | `host_mchegri-3` | `eth0` | Bridge `br0` (Overlay `20.1.1.3`) |

### 5.2 Spine / Route Reflector Configuration: `_mchegri-1`

File: [P3/_mchegri-1](file:///Users/mohamedchegri/Desktop/edu/1337/bgp/P3/_mchegri-1)

```sh
#!/bin/sh

# Router 1 - Spine / Route Reflector (RR)
# Loopback: 1.1.1.1/32
# eth0: 10.1.1.1/30 (to Leaf 1 / _mchegri-2)
# eth1: 10.1.1.5/30 (to Leaf 2 / _mchegri-3)
# eth2: 10.1.1.9/30 (to Leaf 3 / _mchegri-4)

# Enable IPv4 packet forwarding for underlay transit between leaves
sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1 || true

# 1. Configure Linux network interfaces
ip addr replace 1.1.1.1/32 dev lo
ip link set dev lo up

ip addr replace 10.1.1.1/30 dev eth0
ip link set dev eth0 up

ip addr replace 10.1.1.5/30 dev eth1
ip link set dev eth1 up

ip addr replace 10.1.1.9/30 dev eth2
ip link set dev eth2 up

# 2. Configure FRR (OSPF + BGP Route Reflector for EVPN)
vtysh << 'EOF'
configure terminal
!
ip forwarding
!
router ospf
 ospf router-id 1.1.1.1
 network 1.1.1.1/32 area 0
 network 10.1.1.0/30 area 0
 network 10.1.1.4/30 area 0
 network 10.1.1.8/30 area 0
!
router bgp 1
 bgp router-id 1.1.1.1
 neighbor ibgp peer-group
 neighbor ibgp remote-as 1
 neighbor ibgp update-source lo
 ! dynamic neighbors: any leaf loopback in 1.1.1.0/29 may open a session,
 ! no leaf is declared one by one on the RR
 bgp listen range 1.1.1.0/29 peer-group ibgp
 !
 address-family l2vpn evpn
  neighbor ibgp activate
  neighbor ibgp route-reflector-client
 exit-address-family
!
end
write memory
EOF
```

- **Transit Forwarding**: `sysctl -w net.ipv4.ip_forward=1` and `ip forwarding` ensure the spine routes encapsulated underlay UDP packets between leaves.
- **Dynamic Leaf Peering**: `bgp listen range 1.1.1.0/29 peer-group ibgp` dynamically establishes iBGP sessions with any connecting leaf whose source IP is in range `1.1.1.0` through `1.1.1.7`.
- **Pure Control Plane**: The spine has **no** VXLAN interfaces and **no** bridges; it only reflects BGP EVPN routes and routes underlay IP packets.

### 5.3 Leaf / VTEP Configurations: `_mchegri-2`, `_mchegri-3`, `_mchegri-4`

Files: [P3/_mchegri-2](file:///Users/mohamedchegri/Desktop/edu/1337/bgp/P3/_mchegri-2), [P3/_mchegri-3](file:///Users/mohamedchegri/Desktop/edu/1337/bgp/P3/_mchegri-3), [P3/_mchegri-4](file:///Users/mohamedchegri/Desktop/edu/1337/bgp/P3/_mchegri-4)

Example for **Leaf 1** (`_mchegri-2`):
```sh
#!/bin/sh

# Router 2 - Leaf 1 / VTEP
# Loopback: 1.1.1.2/32
# eth0: 10.1.1.2/30 (to Spine / _mchegri-1)
# eth1: connected to host_mchegri-1

# Clean up any existing vxlan/bridge if re-running
ip link del dev vxlan10 2>/dev/null || true
ip link del dev br0 2>/dev/null || true

# 1. Configure Linux network interfaces
ip addr replace 1.1.1.2/32 dev lo
ip link set dev lo up

ip addr replace 10.1.1.2/30 dev eth0
ip link set dev eth0 up

# 2. Setup VXLAN 10 and Bridge br0 (BGP-EVPN control plane learning)
ip link add dev vxlan10 type vxlan id 10 dstport 4789 local 1.1.1.2 nolearning
ip link add dev br0 type bridge
ip link set dev eth1 master br0
ip link set dev vxlan10 master br0
ip link set dev br0 up
ip link set dev vxlan10 up
ip link set dev eth1 up

# 3. Configure FRR (OSPF + iBGP EVPN)
vtysh << 'EOF'
configure terminal
!
router ospf
 ospf router-id 1.1.1.2
 network 1.1.1.2/32 area 0
 network 10.1.1.0/30 area 0
!
router bgp 1
 bgp router-id 1.1.1.2
 neighbor 1.1.1.1 remote-as 1
 neighbor 1.1.1.1 update-source lo
 !
 address-family l2vpn evpn
  neighbor 1.1.1.1 activate
  advertise-all-vni
 exit-address-family
!
end
write memory
EOF
```

- `local 1.1.1.2`: Outer VXLAN packets originate from the router's stable loopback interface.
- `nolearning`: **Crucial setting.** Disables traditional data-plane flood-and-learn on the VXLAN tunnel. MAC learning is delegated entirely to the BGP EVPN control plane.
- `advertise-all-vni`: Instructs FRR to inspect local bridges and advertise all local VNIs and learned MACs as EVPN Type 3 and Type 2 routes.

### 5.4 Host Configurations in P3

Files: [P3/_mchegri-1_host](file:///Users/mohamedchegri/Desktop/edu/1337/bgp/P3/_mchegri-1_host), [P3/_mchegri-2_host](file:///Users/mohamedchegri/Desktop/edu/1337/bgp/P3/_mchegri-2_host), [P3/_mchegri-3_host](file:///Users/mohamedchegri/Desktop/edu/1337/bgp/P3/_mchegri-3_host)

```sh
#!/bin/sh

# Host 1 Configuration (P3)
# Uses eth1 if available (matching the subject diagram), falls back to eth0
IFACE="eth0"
[ -d "/sys/class/net/eth1" ] && IFACE="eth1"

ip addr replace 20.1.1.1/24 dev "$IFACE"
ip link set dev "$IFACE" up
```

### 5.5 EVPN Route Lifecycle (Type 3 vs Type 2)

```text
Phase A: Underlay & BGP Peering Converges (No hosts started yet)
  - Every leaf launches and runs OSPF Area 0.
  - Leaves establish iBGP sessions to Spine (1.1.1.1) from loopbacks.
  - Due to 'advertise-all-vni', each leaf advertises EVPN Route Type 3 (IMET):
      *> [3]:[0]:[32]:[1.1.1.2]
      *> [3]:[0]:[32]:[1.1.1.3]
      *> [3]:[0]:[32]:[1.1.1.4]
  - Result: Every leaf knows the IP of all other VTEPs in VNI 10.
  - Type 2 routes count = 0 (Normal: no host MACs learned yet).

Phase B: Host 1 Starts Up
  - Host 1 (20.1.1.1) starts. Local bridge br0 on Leaf 1 learns Host 1 MAC.
  - Zebra notifies BGPD -> Leaf 1 originates EVPN Route Type 2:
      *> [2]:[0]:[48]:[Host1-MAC] Next-Hop: 1.1.1.2
  - Spine reflects this route to Leaf 2 and Leaf 3.
  - Leaf 2 and Leaf 3 automatically install Host 1 MAC in their kernel FDB:
      bridge fdb show dev vxlan10
      <Host1-MAC> dst 1.1.1.2 self extern_learn

Phase C: Host 2 / Host 3 Start Up
  - Leaf 2 and Leaf 3 originate their own Type 2 routes.
  - Full MAC reachability is established across the fabric without flooding!
```

### 5.6 End-to-End Packet Walk: Host 1 to Host 2 Across the Fabric

1. **Host 1** (`20.1.1.1`) pings **Host 2** (`20.1.1.2`).
2. **Leaf 1** receives the frame on `eth1`. Its bridge `br0` checks `vxlan10`'s FDB table.
3. The entry `<Host2-MAC> dst 1.1.1.3 self extern_learn` already exists thanks to BGP EVPN!
4. Leaf 1 encapsulates the frame into a UDP packet:
   - Outer Source IP: `1.1.1.2` (Leaf 1 loopback)
   - Outer Destination IP: `1.1.1.3` (Leaf 2 loopback)
   - Outer UDP Port: `4789`, VNI: `10`
5. The packet enters the underlay. Leaf 1 checks OSPF route for `1.1.1.3/32` -> Next-hop is Spine (`10.1.1.1` via `eth0`).
6. **Spine** receives the packet on `eth0`. It performs an ordinary IP lookup in its routing table for `1.1.1.3/32` -> routes out `eth1` (`10.1.1.6`) to Leaf 2.
7. **Leaf 2** receives the packet on `eth1`. It strips the VXLAN header and finds the inner Ethernet frame.
8. Leaf 2's `br0` forwards the inner frame out `eth0` directly to **Host 2**.
9. Host 2 generates an ICMP Echo Reply, which follows the exact reverse path.

### 5.7 Wireshark Capture Verification

Capture on Spine interface `eth0`:
- Filter: `icmp or ospf or bgp or vxlan`
- Underlay traffic: OSPF Hellos to `224.0.0.5`, BGP TCP 179 updates reflecting Type 2/3 routes.
- Overlay traffic: VXLAN packets with outer source `1.1.1.2` and destination `1.1.1.3`/`1.1.1.4`, carrying tenant ICMP packets.

---

## 6. Step-by-Step GNS3 Setup Guide

### 6.1 Creating Docker Templates

In GNS3: **Edit > Preferences > Docker > Docker containers > New**:

1. **Host Template**:
   - Name: `host_mchegri`
   - Image: `host_mchegri:latest`
   - Console type: `telnet`
   - Network adapters: **`2`** (ensures both `eth0` and `eth1` exist)

2. **Router Template**:
   - Name: `routeur_mchegri`
   - Image: `routeur_mchegri:latest`
   - Console type: `telnet`
   - Network adapters: **`4`** (provides `eth0` through `eth3` for spine uplinks)

### 6.2 Building Topologies & Cabling Rules

1. Create a new blank project for each part (`P1`, `P2`, `P3`).
2. Drag devices onto the workspace and **rename them using the login `mchegri`**:
   - P1: `host_mchegri-1`, `routeur_mchegri`
   - P2: `host_mchegri-1`, `routeur_mchegri-1`, `Switch_mchegri`, `routeur_mchegri-2`, `host_mchegri-2`
   - P3: `_mchegri-1` (spine), `_mchegri-2/3/4` (leaves), `host_mchegri-1/2/3`
3. Wire links strictly according to the cabling tables (see §4.1 for P2 and §5.1 for P3).
4. Start all nodes.

### 6.3 Applying Configurations

Double-click each node to open its telnet terminal and paste the script contents, or use Docker CLI from the host terminal:

```sh
# Example: copying config script into a running GNS3 container
docker ps --format '{{.Names}}'
docker cp P3/_mchegri-1 <container-name>:/tmp/conf.sh
docker exec -it <container-name> sh /tmp/conf.sh
```

### 6.4 Exporting Portable Projects (`.gns3project`)

> [!IMPORTANT]
> The subject strictly requires portable project archives with base images visible in your git repository:
> - In GNS3: Navigate to **File > Export portable project**
> - Ensure **Include base images** is checked
> - Save the exports as:
>   - `P1/P1.gns3project`
>   - `P2/P2.gns3project`
>   - `P3/P3.gns3project`

---

## 7. Master Diagnostic & Command Cheat Sheet

### 7.1 Linux Network Commands (`ip`, `bridge`, `brctl`)

```sh
# Address & Link Inspection
ip addr                                 # Display all interface IP addresses
ip -d link show vxlan10                 # Show full details of vxlan10 (VNI, local IP, remote/group, port)
ip link set dev eth0 up                 # Bring an interface UP

# Bridge & Forwarding Database Inspection
brctl show                              # List bridges and attached member ports
brctl showmacs br0                      # List MAC addresses learned by the software bridge
bridge fdb show dev vxlan10             # Show VXLAN FDB (displays remote MAC -> VTEP mapping and extern_learn)
bridge link                             # Show operational status of bridge ports

# Multicast & Routing
ip maddr show dev eth0                  # Show joined IGMP multicast groups on eth0
ip route                                # Show Linux kernel IP routing table
```

### 7.2 FRRouting `vtysh` Commands

```sh
vtysh -c 'show daemons'                 # Verify running daemons (zebra, ospfd, bgpd, isisd)
vtysh -c 'show ip route'                # Show routing table (O = OSPF, B = BGP, C = Connected, > = Best)
vtysh -c 'show ip ospf neighbor'        # Show OSPF neighbor state (should be Full/Backup or Full/DROther)
vtysh -c 'show ip ospf interface'       # Show OSPF interface configuration, timers and areas
vtysh -c 'show bgp summary'             # Summary of all BGP sessions
vtysh -c 'show bgp l2vpn evpn summary'  # Summary of BGP EVPN peering sessions (look for * for dynamic peers)
vtysh -c 'show bgp l2vpn evpn'          # Display EVPN route table (Type 3 IMET and Type 2 MAC routes)
vtysh -c 'show evpn vni'                # Show VNIs known to Zebra and their associated VTEP count
vtysh -c 'show evpn mac vni 10'         # Show MAC addresses learned per VNI (Local vs Remote)
```

### 7.3 Packet Capture & Wireshark Display Filters

```sh
# Capturing on router interfaces with tcpdump
tcpdump -ni eth0 udp port 4789          # Capture only VXLAN encapsulated packets
tcpdump -ni eth0 proto ospf             # Capture OSPF protocol 89 packets
tcpdump -ni eth0 tcp port 179           # Capture BGP sessions

# Wireshark Display Filters
vxlan                                   # Filter all VXLAN traffic
ospf                                    # Filter OSPF hellos and LSAs
bgp                                     # Filter BGP OPEN, KEEPALIVE, and UPDATE packets
icmp                                    # Filter tenant ping traffic
arp                                     # Filter ARP resolution requests and replies
```

---

## 8. Comprehensive Troubleshooting Matrix

| Symptom | Probable Cause | Diagnostic Command | Immediate Resolution |
| :--- | :--- | :--- | :--- |
| `RTNETLINK answers: File exists` | Script run multiple times without prior teardown | `ip link show` | Scripts now include `ip link del dev vxlan10` and `ip addr replace`. If manual, run `ip link del dev vxlan10; ip link del dev br0`. |
| `Cannot find device "eth1"` / `"eth2"` | Router or host template configured with insufficient adapters | `ip link` inside node | Router template requires 4 adapters. Host scripts now auto-detect `eth1` or fall back to `eth0`. |
| **P2: Ping fails** | Port not enrolled in bridge, interface down, or IP mismatch | `brctl show br0`, `ip link` | Verify `eth1` and `vxlan10` are `master br0`, interfaces are `UP`, and host IPs belong to `30.1.1.0/24`. |
| **P2 Multicast: Ping fails** | Switch dropped IGMP/multicast, or group mismatch | `ip maddr show dev eth0` | Verify `239.1.1.1` is listed on `eth0` and standard GNS3 switch is utilized. |
| **P3: OSPF Neighbor Stuck** | Subnet mismatch on `/30` point-to-point link or swapped cabling | `vtysh -c 'show ip ospf neighbor'` | Verify link IPs match: Spine `eth0` (`10.1.1.1`) <-> Leaf 1 `eth0` (`10.1.1.2`). |
| **P3: BGP in Active / Connect** | Underlay OSPF route to loopback missing | `vtysh -c 'show ip route 1.1.1.1'` | Wait ~30s for OSPF to converge. Test underlay reachability with `ping -I 1.1.1.2 1.1.1.1`. |
| **P3: 0 EVPN Routes Visible** | `advertise-all-vni` missing on leaf or EVPN family not activated | `vtysh -c 'show running-config'` | Verify `address-family l2vpn evpn` contains `advertise-all-vni` on leaves and `activate` on RR. |
| **P3: Underlay Ping OK, Overlay Ping Fails** | Spine not forwarding transit packets | `sysctl net.ipv4.ip_forward` on spine | Run `sysctl -w net.ipv4.ip_forward=1` and set `ip forwarding` inside vtysh on `_mchegri-1`. |
| **P3: Type 3 OK, No Type 2 Routes** | Host container inactive or local port down | `brctl showmacs br0` on leaf | Start the host container; bridge must receive at least one packet from the host to generate Type 2 route. |

---

## 9. Peer-Evaluation Defense Guide

### 9.1 Step-by-Step Live Demonstration Workflow

1. **Repository Layout**:
   - Run `find -maxdepth 2 -ls` from the repository root to verify folder structure.
   - Run `file P*/P*.gns3project` to prove exported portable archives are valid ZIP files.
2. **Part 1 Demo**:
   - Open [P1/_mchegri-1_host](file:///Users/mohamedchegri/Desktop/edu/1337/bgp/P1/_mchegri-1_host) and [P1/_mchegri-2](file:///Users/mohamedchegri/Desktop/edu/1337/bgp/P1/_mchegri-2), explaining each line.
   - Start the P1 topology in GNS3.
   - Inside the router console, run `vtysh -c 'show daemons'` (shows `zebra`, `ospfd`, `bgpd`, `isisd`).
   - Run `ip addr` to prove zero IP addresses exist by default.
3. **Part 2 Static Demo**:
   - Apply `_mchegri-1_s`, `_mchegri-2_s`, and host scripts.
   - Run `ip -d link show vxlan10` showing `remote 10.1.1.X` and `dstport 4789`.
   - Ping from Host 1 (`30.1.1.1`) to Host 2 (`30.1.1.2`).
   - Show Wireshark capture of UDP 4789 encapsulated ICMP packets.
4. **Part 2 Multicast Demo**:
   - Apply `_mchegri-1_g` and `_mchegri-2_g`.
   - Run `ip -d link show vxlan10` showing `group 239.1.1.1`.
   - Ping again and inspect `brctl showmacs br0`.
   - Show initial ARP broadcast sent to `239.1.1.1` in Wireshark.
5. **Part 3 EVPN Demo**:
   - Apply router scripts `_mchegri-1` through `_mchegri-4`.
   - Run `vtysh -c 'show ip route'` on Leaf 3 showing loopbacks learned via OSPF.
   - On the Spine, run `vtysh -c 'show bgp l2vpn evpn summary'` showing 3 dynamic `*` leaf sessions.
   - Run `vtysh -c 'show bgp l2vpn evpn'` showing **only Type 3 routes** initially.
   - Start Host 1 -> Show instant creation of **Type 2 route** on Leaf 1 and reflected to Leaf 3.
   - Start Host 2 and Host 3 -> Show ping between all hosts.
   - Show Wireshark capture demonstrating VXLAN overlay packets crossing the spine.

### 9.2 Theoretical Questions & Model Answers

#### General & Docker
- **Q: Why use Docker containers instead of full virtual machines?**
  - *A*: Docker containers share the host Linux kernel, boot in milliseconds, and utilize minimal RAM. Because Linux networking primitives (bridges, namespaces, VXLAN) exist in the kernel, containers provide full Layer 2/3 fidelity without VM virtualization overhead.
- **Q: Why is it critical that images configure no default IP addresses?**
  - *A*: The subject requires reusable generic base images. Hardcoding IP addresses violates node independence, causing IP address collisions when multiple containers launch from the same image.

#### FRRouting & Routing Daemons
- **Q: What is FRRouting, and what role does `zebra` play?**
  - *A*: FRR is an open-source IP routing protocol suite (fork of Quagga). `zebra` acts as the kernel routing manager (RIB). Protocol daemons (`bgpd`, `ospfd`) calculate best paths and send them to `zebra`, which installs them into the Linux kernel forwarding database (FIB). In EVPN, `zebra` also listens for kernel bridge MAC learning events and notifies `bgpd`.
- **Q: What is `watchfrr`?**
  - *A*: A watchdog supervisor daemon that launches, monitors, and restarts FRR protocol daemons if they crash.

#### VXLAN & Bridging
- **Q: What is a VTEP?**
  - *A*: VXLAN Tunnel End Point. An entity that originates and terminates VXLAN tunnels by encapsulating inner Ethernet frames into UDP packets and decapsulating incoming packets.
- **Q: What is BUM traffic?**
  - *A*: Broadcast, Unknown unicast, and Multicast traffic. In traditional Ethernet, these frames must reach all stations on the segment. In Part 2 multicast, BUM is replicated via `239.1.1.1`. In Part 3 EVPN, BUM is handled via ingress (head-end) replication using Type 3 routes.
- **Q: What is the purpose of `nolearning` on the VXLAN interface in P3?**
  - *A*: `nolearning` stops the Linux kernel from automatically updating its FDB from incoming data packets. Instead, all remote MAC addresses must be installed programmatically by BGP EVPN, maintaining strict control plane integrity.

#### OSPF & BGP EVPN
- **Q: Why do we need OSPF in Part 3 if BGP is used?**
  - *A*: OSPF serves as the **underlay IGP**. BGP is an application-layer routing protocol running over TCP 179; it cannot route its own packets without underlying IP reachability between loopback addresses.
- **Q: Why configure BGP peering between loopback addresses (`update-source lo`)?**
  - *A*: Physical links can fail. If a router has redundant physical paths, peering between loopback addresses ensures the BGP TCP session remains established as long as any physical path is reachable via OSPF.
- **Q: What is an EVPN Type 2 route vs Type 3 route?**
  - *A*:
    - **Type 3 (IMET)** advertises VTEP presence in a VNI for BUM replication.
    - **Type 2 (MAC/IP Advertisement)** advertises that a specific host MAC/IP address has been learned behind a VTEP.
- **Q: Why is the spine configured as a Route Reflector?**
  - *A*: Under the iBGP split-horizon rule, an iBGP router will not re-advertise routes learned from an iBGP peer. Without a Route Reflector, all 3 leaves would need direct iBGP peering with each other (full mesh). The RR reflects leaf routes, allowing leaves to maintain only one session to the spine.

---

## 10. References & RFCs

- **[RFC 7348](https://datatracker.ietf.org/doc/html/rfc7348)**: Virtual eXtensible Local Area Network (VXLAN): A Framework for Overlaying Virtualized Layer 2 Networks over Layer 3 Networks.
- **[RFC 7432](https://datatracker.ietf.org/doc/html/rfc7432)**: BGP MPLS-Based Ethernet VPN (EVPN).
- **[RFC 8365](https://datatracker.ietf.org/doc/html/rfc8365)**: A Network Virtualization Overlay Solution Using Ethernet VPN (EVPN with VXLAN).
- **[RFC 4271](https://datatracker.ietf.org/doc/html/rfc4271)**: A Border Gateway Protocol 4 (BGP-4).
- **[RFC 4760](https://datatracker.ietf.org/doc/html/rfc4760)**: Multiprotocol Extensions for BGP-4 (MP-BGP).
- **[RFC 4456](https://datatracker.ietf.org/doc/html/rfc4456)**: BGP Route Reflection: An Alternative to Full Mesh Internal BGP (iBGP).
- **[RFC 2328](https://datatracker.ietf.org/doc/html/rfc2328)**: OSPF Version 2.
- **FRRouting Official Documentation**: <https://docs.frrouting.org/>
- **Vincent Bernat**: *VXLAN & Linux* (<https://vincent.bernat.ch/en/blog/2017-vxlan-linux>) and *VXLAN: BGP EVPN with FRR* (<https://vincent.bernat.ch/en/blog/2017-vxlan-bgp-evpn>).
