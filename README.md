# BADASS: BGP At Doors of Autonomous Systems is Simple

A comprehensive implementation and theoretical guide for the **42 Network BADASS** project. This project explores modern data center network architecture by building simulated network topologies in **GNS3** (Graphical Network Simulator 3, an application where you draw a network and run virtual devices in it) with **Docker** containers (isolated programs that share the host's Linux kernel, much lighter than virtual machines), progressing from basic image creation to **VXLAN** tunneling and **BGP EVPN** control-plane fabric automation. Each of these terms is explained in the sections below.

Login used across all devices, scripts, and images: **`mchegri`**.

> **How to read this manual:** every technical term is defined in plain words the first time it appears in the text. If you jump into the middle and meet an unknown word, look it up in the [Glossary](#11-glossary).

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
    - [Packet Routing Software: zebra, Quagga \& FRR](#packet-routing-software-zebra-quagga--frr)
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
  - [4.8 Testing Procedure \& Verification](#48-testing-procedure--verification)
- [5. Part 3: Clos Spine-Leaf Fabric with BGP EVPN](#5-part-3-clos-spine-leaf-fabric-with-bgp-evpn)
  - [5.1 Clos Spine-Leaf Architecture \& Interface Mapping](#51-clos-spine-leaf-architecture--interface-mapping)
  - [5.2 Spine / Route Reflector Configuration: `_mchegri-1`](#52-spine--route-reflector-configuration-_mchegri-1)
  - [5.3 Leaf / VTEP Configurations: `_mchegri-2`, `_mchegri-3`, `_mchegri-4`](#53-leaf--vtep-configurations-_mchegri-2-_mchegri-3-_mchegri-4)
  - [5.4 Host Configurations in P3](#54-host-configurations-in-p3)
  - [5.5 EVPN Route Lifecycle (Type 3 vs Type 2)](#55-evpn-route-lifecycle-type-3-vs-type-2)
  - [5.6 End-to-End Packet Walk: Host 1 to Host 2 Across the Fabric](#56-end-to-end-packet-walk-host-1-to-host-2-across-the-fabric)
  - [5.7 Wireshark Capture Verification](#57-wireshark-capture-verification)
  - [5.8 Testing Procedure \& Expected Output](#58-testing-procedure--expected-output)
- [6. Step-by-Step GNS3 Setup Guide](#6-step-by-step-gns3-setup-guide)
  - [6.1 Installing GNS3 \& Prerequisites (Kali Linux)](#61-installing-gns3--prerequisites-kali-linux)
  - [6.2 First Launch \& Setup Wizard](#62-first-launch--setup-wizard)
  - [6.3 Creating the Docker Templates](#63-creating-the-docker-templates)
  - [6.4 Building the P1 Topology](#64-building-the-p1-topology)
  - [6.5 Verifying P1](#65-verifying-p1)
  - [6.6 Building the P2 \& P3 Topologies](#66-building-the-p2--p3-topologies)
  - [6.7 Applying Configurations](#67-applying-configurations)
  - [6.8 Exporting Portable Projects (`.gns3project`)](#68-exporting-portable-projects-gns3project)
- [7. Master Diagnostic \& Command Cheat Sheet](#7-master-diagnostic--command-cheat-sheet)
  - [7.1 Linux Network Commands (`ip`, `bridge`, `brctl`)](#71-linux-network-commands-ip-bridge-brctl)
  - [7.2 FRRouting `vtysh` Commands](#72-frrouting-vtysh-commands)
  - [7.3 Packet Capture \& Wireshark Display Filters](#73-packet-capture--wireshark-display-filters)
- [8. Comprehensive Troubleshooting Matrix](#8-comprehensive-troubleshooting-matrix)
- [9. Peer-Evaluation Defense Guide](#9-peer-evaluation-defense-guide)
  - [9.1 Step-by-Step Live Demonstration Workflow](#91-step-by-step-live-demonstration-workflow)
  - [9.2 Theoretical Questions \& Model Answers](#92-theoretical-questions--model-answers)
- [10. References \& RFCs](#10-references--rfcs)
- [11. Glossary](#11-glossary)

---

## 1. Executive Overview & Architecture

### 1.1 The Problem: Why Traditional VLANs Fail at Scale

#### Two basic ideas first: Layer 2 and Layer 3

Computers talk to each other at two different levels. Think of a building:

- **Layer 2 (L2)** is like talking **inside one room**. Machines on the same local network talk directly, without a router. Each machine is identified by its **MAC address**, the hardware address of its network card (e.g. `aa:bb:cc:dd:ee:ff`). The data they send is called an **Ethernet frame**: a small block with the destination MAC, the source MAC, and the content. A **switch** is the box that connects machines in the same room and delivers each frame to the right MAC.
- **Layer 3 (L3)** is like sending mail **between buildings**. Machines are identified by their **IP address** (e.g. `30.1.1.1`), and **routers** carry **packets** from one network to another.

Two more words used everywhere in this manual:

- A **subnet** is a range of IP addresses that belong to the same local network. `30.1.1.0/24` means "every address that starts with `30.1.1`".
- A **broadcast domain** is the group of machines that receive a message sent "to everyone". In practice, it is everybody in the same L2 "room".

A good example of a message sent to everyone is **ARP** (Address Resolution Protocol). A machine that wants to talk to `30.1.1.2` knows the IP but not the MAC. So it shouts to the whole room: *"Who has `30.1.1.2`? Tell me your MAC."* Only the owner answers, but everybody hears the question.

#### What a cloud data center needs

A cloud data center is one big set of servers and cables shared by many customers. Each customer is called a **tenant**. Tenant A's machines and Tenant B's machines may run on the same physical servers.

Each tenant wants **its own private L2 room**:
- its machines can talk to each other as if they were plugged into the same switch, even when they run on servers far apart;
- they never see the other tenants' traffic.

This is what "**isolation at Layer 2**" means.

#### The old solution: VLANs and Spanning Tree

The classic way to split one physical network into several private rooms is the **VLAN** (Virtual LAN). Each Ethernet frame gets a small **tag** with a number, the VLAN ID. Switches only deliver a frame to ports that belong to the same VLAN number. The tag format is defined by the standard **IEEE 802.1Q**.

Switch networks also use **STP** (Spanning Tree Protocol). If switches are cabled in a loop, a frame could circle forever. STP prevents this by switching off (blocking) some cables.

```
Traditional L2 Network (Spanning Tree blocks redundant links)
   [Switch A] ═════ (Blocked by STP) ═════ [Switch B]
        \                                      /
         \                                    /
          ─────── [Access Switch / Host] ────
```

#### Why this does not work for a big cloud

1. **Not enough VLAN numbers.** The VLAN ID has only 12 bits, so there are at most $2^{12} - 2 = 4,094$ usable VLANs. A big cloud has tens of thousands of tenants. There are simply not enough numbers.
2. **Wasted cables.** Data centers cable every switch twice, so that one cable can fail without cutting the network. But STP blocks one of the two cables to avoid loops. Half of the bandwidth you paid for sits idle.
3. **Too much shouting.** Every broadcast (like an ARP question) is copied to every port of the VLAN. With thousands of machines in one room, these copies waste bandwidth and CPU on every server.

### 1.2 The Solution: Overlay / Underlay Network Architecture

#### The idea: a virtual network on top of the real one

Modern data centers separate the network into two levels:

- The **underlay** is the **real** network: the physical cables and routers. It only knows IP addresses and moves IP packets (L3).
- The **overlay** is a **virtual** network built on top of it. This is where each tenant gets its private L2 room.

An everyday comparison: when you make a phone call, you just talk to the other person (the overlay). You never see the antennas and cables in between (the underlay).

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

Read the diagram from top to bottom: Host 1 and Host 2 believe they are in the same room. In reality, their frames travel through the routers below.

#### How it works: the envelope trick (VXLAN)

How can an L2 frame cross an L3 network of routers? By putting it in an envelope.

1. Host 1 sends a normal Ethernet frame to Host 2.
2. The router next to Host 1 puts the **whole frame** inside a normal IP packet addressed to the router next to Host 2. Wrapping a frame inside another packet like this is called **encapsulation**, like putting a letter inside a second envelope.
3. The underlay routers carry this packet like any other IP packet. They never open it.
4. The router next to Host 2 opens the envelope and delivers the original frame to Host 2.

The protocol that does this wrapping is **VXLAN** (Virtual eXtensible LAN). The envelope is a **UDP** packet sent to port `4789`. **UDP** (User Datagram Protocol) is a simple way to send a packet to a port number, with no connection setup and no resending if it is lost.

Each private room gets a number, the **VNI** (VXLAN Network Identifier). The VNI plays the same role as the VLAN ID, but it has 24 bits, so there are about 16 million possible rooms instead of 4,094.

#### How each problem from §1.1 is solved

| Problem with VLANs | Solution with underlay / overlay |
| :--- | :--- |
| Only 4,094 VLAN numbers | VXLAN uses a 24-bit VNI: about 16 million private networks. |
| STP blocks half the cables | The underlay is routed (L3), and routers do not need STP. All cables are used at the same time thanks to **ECMP** (Equal-Cost Multi-Path: when several paths are equally good, traffic is shared between all of them). The routes are computed by a routing protocol such as **OSPF** (§2.2) or **eBGP** (external BGP, §2.3). |
| Broadcasts flood everyone | Routers exchange the list of "which MAC is where" in advance, with **BGP EVPN** (see below). They no longer need to shout to find a machine. |

#### Who decides where frames go: the control plane (BGP EVPN)

Every network does two different jobs:

- The **data plane** **moves** the packets (the delivery trucks).
- The **control plane** **decides** where they should go (the map and the GPS).

Without a control plane, a VXLAN router learns where machines are by **flood-and-learn**: when it gets a frame for an unknown MAC, it sends a copy to everybody, then remembers where the answer came from. This works, but it is the same "shouting" problem as before.

With **BGP EVPN** (Ethernet VPN, an extension of the BGP routing protocol, §2.4), each router tells the others in advance: *"MAC `aa:bb:...` is behind me."* Every router then already knows where to send each frame, without shouting. Part 2 of this project uses flood-and-learn, and Part 3 replaces it with BGP EVPN.

### 1.3 Project Progression: P1, P2, and P3

- **Part 1 (P1)**: Construction of two minimal, compliant base Docker **images** (an image is the read-only template a container is started from): a generic Linux host container and a routing engine container running **FRRouting** (FRR, open-source routing software, §3.2) with its daemons `zebra`, `bgpd`, `ospfd`, and `isisd` (a **daemon** is a program that runs in the background).
- **Part 2 (P2)**: Establishing an L2 overlay across a routed L3 underlay using VXLAN with **VNI** 10 (VXLAN Network Identifier: a 24-bit number saying which virtual network a frame belongs to, like a VLAN ID but with 16 million possible values) and a **software bridge** `br0` (a virtual switch inside the Linux kernel). Evaluated first in **static unicast mode** (**unicast** = sent to one single destination), then in **dynamic multicast mode** (**multicast** = sent to a group address, here `239.1.1.1`, that any interested machine can join).
- **Part 3 (P3)**: Building a carrier-grade data center **Clos spine-leaf fabric** (two layers of routers: every **leaf**, where hosts plug in, is cabled to every **spine**, the core; any host reaches any other in leaf → spine → leaf) with 1 **Route Reflector** spine (a BGP router that relays routes between the leaves, §2.5), 3 **VTEP** leaves (VXLAN Tunnel End Point: the router that wraps and unwraps VXLAN packets), and 3 hosts. The underlay routes traffic with OSPF **Area 0** (the backbone area of OSPF), while **iBGP** (internal BGP, §2.3) EVPN dynamically exchanges MAC reachability with zero flood-and-learn.

### 1.4 Repository Structure

```text
bgp/
├── README.md               # Single manual: theory, configs, GNS3 guide, testing & defense notes
├── en.subject.pdf          # Official 42 project specification
├── P1/
│   ├── _mchegri-1_host     # Dockerfile: Host image (Alpine + BusyBox + iproute2 + ping)
│   ├── _mchegri-2          # Dockerfile: Router image (FRRouting 9.1.3 + daemons + tcpdump)
│   └── build.sh            # Build script tagging host_mchegri and routeur_mchegri
├── P2/
│   ├── _mchegri-1_s        # Router 1: VXLAN static unicast configuration script
│   ├── _mchegri-2_s        # Router 2: VXLAN static unicast configuration script
│   ├── _mchegri-1_g        # Router 1: VXLAN multicast group configuration script
│   ├── _mchegri-2_g        # Router 2: VXLAN multicast group configuration script
│   ├── _mchegri-1_host     # Host 1: IP configuration script (30.1.1.1/24)
│   └── _mchegri-2_host     # Host 2: IP configuration script (30.1.1.2/24)
└── P3/
    ├── _mchegri-1          # Spine Router: OSPF Area 0 + BGP Route Reflector for EVPN
    ├── _mchegri-2          # Leaf 1 Router: VTEP (lo: 1.1.1.2) + OSPF + iBGP EVPN
    ├── _mchegri-3          # Leaf 2 Router: VTEP (lo: 1.1.1.3) + OSPF + iBGP EVPN
    ├── _mchegri-4          # Leaf 3 Router: VTEP (lo: 1.1.1.4) + OSPF + iBGP EVPN
    ├── _mchegri-1_host     # Host 1: IP configuration script (20.1.1.1/24)
    ├── _mchegri-2_host     # Host 2: IP configuration script (20.1.1.2/24)
    └── _mchegri-3_host     # Host 3: IP configuration script (20.1.1.3/24)
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

- **Prefix length (`/24`, `/30`, `/32`)**: the number after the slash is how many leading bits of the address are fixed (the network part). `/24` leaves 8 bits for hosts (254 usable addresses). `/30` leaves 2 bits: 2 usable addresses, exactly one per end of a **point-to-point link** (a cable between just two routers). `/32` is one single address.
- **Loopback** (`lo`): a virtual interface inside the router that is always up, even if a cable is cut. Its `/32` address is used as the router's stable identity.

---

## 2. Theoretical Foundations & Protocols

### 2.1 OSI Stack & Encapsulation Overhead

The **OSI model** describes networking as 7 stacked layers, each one using the layer below. The ones that matter here are **L2** data link (Ethernet, MAC addresses), **L3** network (IP addresses, routing) and **L4** transport (**TCP**, the reliable connection-based protocol, and **UDP**, the simple connectionless one). Each layer adds its own **header** (control information) in front of the data.

VXLAN encapsulates Layer 2 Ethernet frames inside Layer 4 UDP **datagrams** (a datagram is one UDP packet). The outer headers carry the packet across the underlay; the inner frame is the tenant's original frame, untouched:

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
- **MTU Implication**: the **MTU** (Maximum Transmission Unit) is the biggest packet an interface can send in one piece; standard Ethernet MTU is 1500 bytes. Adding 50 bytes to a full-size frame makes it too big, so it would need **fragmentation** (splitting into several packets, which costs performance). To avoid it, physical switch interfaces in a real data center must support **Jumbo Frames** (frames bigger than 1500 bytes: typically MTU $\ge 1550$ bytes, commonly 9000 or 9216 bytes). Inside GNS3 Docker containers, Linux handles this transparently in software.

### 2.2 OSPFv2 (Open Shortest Path First)

OSPF ([RFC 2328](https://datatracker.ietf.org/doc/html/rfc2328); an **RFC** is a numbered Internet standard document) is an **interior** routing protocol, also called an **IGP** (Interior Gateway Protocol), meaning it runs inside one **Autonomous System** (**AS**: a network run by one organization under one routing policy, identified by a number; this project uses AS `1`). It is **link-state**: every router learns the full map of the network, not just "next hop" hints from its neighbours.
- **Operation**: Routers exchange Link-State Advertisements (**LSAs**) to build an identical map (Link-State Database / LSDB) of the network topology. Every router then independently computes the shortest path tree using Dijkstra's algorithm.
- **Area 0 (Backbone)**: All OSPF areas must connect to the central backbone area. In Part 3, the entire underlay fabric resides in Area 0.
- **Multicast Transport**: OSPF routers discover **neighbors** (directly connected routers that also run OSPF) by sending small **Hello** packets to the IPv4 multicast address `224.0.0.5` (`AllSPFRouters`). OSPF runs directly on IP as protocol number 89, without TCP or UDP.
- **Purpose in P3**: Provides loopback-to-loopback reachability (`1.1.1.1/32` through `1.1.1.4/32`) so that iBGP TCP sessions and VXLAN UDP tunnels can establish reliably across any physical path.

### 2.3 BGP-4 & Multiprotocol BGP (MP-BGP)

Border Gateway Protocol ([RFC 4271](https://datatracker.ietf.org/doc/html/rfc4271)) is the routing protocol of the Internet. It is **path-vector**: each route carries the list of ASes it went through, which is used to choose paths and to avoid loops. Two BGP routers that talk to each other are **peers** (or neighbors); their conversation is a **session** running over reliable **TCP** on port **179**.
- **iBGP vs eBGP**: BGP sessions between routers in the same Autonomous System (AS) are **Internal BGP (iBGP)**. Sessions between different ASes are **External BGP (eBGP)**.
- **Split-Horizon Rule**: To prevent routing loops within an AS, a standard iBGP router will **never** re-advertise a route learned from an iBGP peer to another iBGP peer. Consequently, traditional iBGP requires a full mesh ($N \times (N - 1) / 2$ sessions).
- **MP-BGP Extensions ([RFC 4760](https://datatracker.ietf.org/doc/html/rfc4760))**: Multiprotocol BGP lets one BGP session carry several kinds of routes. Each kind is an **address family**, named by two numbers: the **AFI** (Address Family Identifier, e.g. IPv4, IPv6, L2VPN) and the **SAFI** (Subsequent AFI, the sub-type). The routes themselves are called **NLRI** (Network Layer Reachability Information: "this destination is reachable through me"). Supported families include IPv6, VPNv4, and **L2VPN EVPN** (AFI 25, SAFI 70), the one used in P3.

### 2.4 BGP EVPN (RFC 7432 / RFC 8365)

Ethernet VPN (EVPN) transforms BGP into a unified control plane for Layer 2 and Layer 3 overlays. In our architecture, the VTEPs publish routes into BGP instead of relying on data-plane flooding. Two terms used below:
- **BUM traffic**: Broadcast, Unknown unicast (a frame for a MAC nobody has learned yet) and Multicast. These frames must reach every member of the L2 network, so each VTEP needs the list of the others.
- **FDB** (Forwarding Database): the table in which a bridge records "MAC address X is reachable through port Y". For `vxlan10`, the "port" is the IP of the remote VTEP.


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

To eliminate the need for an $O(N^2)$ iBGP **full mesh** (every router peering with every other one) between leaves, the spine router acts as a **Route Reflector (RR)** ([RFC 4456](https://datatracker.ietf.org/doc/html/rfc4456)):
- The spine marks all leaves as `route-reflector-client` (a router whose routes the RR is allowed to relay to the others).
- When Leaf 1 advertises an EVPN route to the RR, the RR re-advertises ("reflects") that route to Leaf 2 and Leaf 3, safely bypassing the iBGP split-horizon rule.
- **Dynamic Neighbors**: Rather than configuring every leaf IP manually on the spine, FRR provides `bgp listen range 1.1.1.0/29 peer-group ibgp`. A **peer group** is a named set of neighbors that share the same settings, configured once. Any leaf initiating a BGP connection with a loopback inside `1.1.1.0/29` (`1.1.1.1` to `1.1.1.6`) is automatically accepted into the peer group.

### 2.6 IS-IS (Intermediate System to Intermediate System)

IS-IS ([RFC 1195](https://datatracker.ietf.org/doc/html/rfc1195)) is a link-state interior routing protocol, like OSPF, designed by ISO (International Organization for Standardization). Its packets travel directly in Layer 2 frames, not inside IP packets.
- **Requirement in P1**: The subject requires `isisd` to be active and configured in the router image along with `zebra`, `bgpd`, and `ospfd`. In modern ISP and data center networks, IS-IS is widely utilized as an alternative to OSPF.

---

## 3. Part 1: Base Docker Images & GNS3 Integration

Part 1 requires creating two custom Docker images that serve as generic building blocks throughout P1, P2, and P3.

### 3.1 Host Image: `_mchegri-1_host`

File: [P1/_mchegri-1_host](P1/_mchegri-1_host)

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
- **Utilities**: a host only needs to get an IP address and test reachability, so the image installs just four packages:

  | Package | Commands | Why the host needs it |
  |---|---|---|
  | `busybox` | `sh`, `ls`, `cat`, `vi`, ... | Shell and basic Unix commands in a single binary. Already in Alpine, listed to make the requirement explicit. |
  | `iproute2` | `ip addr`, `ip link`, `ip route` | Assign addresses in P2/P3, e.g. `ip addr add 30.1.1.1/24 dev eth1`. Full version of the limited BusyBox `ip`. |
  | `net-tools` | `ifconfig`, `route`, `netstat`, `arp` | Legacy tools, handy for anyone who prefers `ifconfig`. |
  | `iputils` | `ping`, `tracepath`, `arping` | Test connectivity between hosts across the VXLAN (P2) and the BGP-EVPN fabric (P3). |

- **`apk add --no-cache`**: installing a package downloads two things:
  - **The index** (`APKINDEX.tar.gz`): a catalog of every package in the repository, with its version, dependencies and checksum. It contains no programs, only the list `apk` reads to know what to download.
  - **The package** (e.g. `iputils-xxx.apk`): an archive with the real binaries (e.g. `/bin/ping`). `apk` extracts them into the filesystem, then deletes the archive.

  Without the flag, `apk update` saves the index in `/var/cache/apk/` for later use. In Docker, every file left on disk when a `RUN` line ends is saved in the image layer for good, so that unused catalog would ship inside the image. `--no-cache` downloads the index, uses it, and does not save it. It is the same as the older `apk update && apk add ... && rm -rf /var/cache/apk/*`.

  | What | Downloaded? | Kept in the image? |
  |---|---|---|
  | Index (`APKINDEX`) | yes | no, because of `--no-cache` |
  | Package archive (`.apk`) | yes | no, deleted after extraction |
  | Binaries (`ping`, `ip`, `ifconfig`) | yes, inside the archive | yes |

  `apk add --no-cache` already fetches a fresh index by itself, so the `apk update` before it downloads the index a second time: redundant but harmless.
- **Subject Constraint**: No IP address is configured inside the image.

### 3.2 Router Image: `_mchegri-2`

File: [P1/_mchegri-2](P1/_mchegri-2)

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

#### Packet Routing Software: zebra, Quagga & FRR

The subject asks for "a software that manages packet routing (zebra or quagga)". Two different jobs are involved: **forwarding** packets and **deciding the routes**.

1. **Forwarding is done by the Linux kernel.** When a packet arrives on `eth0`, the kernel looks up its destination in the routing table (`ip route`) and sends it out of the matching interface. The kernel is fast, but it knows no routes by itself: only the ones someone puts in its table. Adding them by hand (`ip route add 10.0.0.0/24 via 1.1.1.2`) does not scale to many routers and links that go up and down.
2. **Deciding the routes is done by the routing software.** It talks to neighbouring routers with routing protocols (OSPF, BGP, IS-IS), learns which networks exist and the best path to each, and writes those routes into the kernel table automatically.
   - **Quagga** is the old routing suite, no longer really maintained.
   - **FRRouting (FRR)** is the maintained fork of Quagga, used by this image. Same design, same daemon names.

FRR is not one program but a set of small daemons, with **zebra** in the middle:

```text
   bgpd        ospfd        isisd       <- protocol daemons: talk to neighbours,
     \           |           /             learn routes
      \          |          /
       └──────  zebra  ─────┘           <- collects all routes (RIB), picks the best
                 |                         one for each destination
                 | netlink
                 ▼
        Linux kernel routing table      <- actually forwards the packets (FIB)
```

- **Protocol daemons** (`bgpd`, `ospfd`, `isisd`) each run one protocol. They never touch the kernel directly: they hand the routes they learn to zebra.
- **zebra** keeps the list of all known routes, the **RIB** (Routing Information Base). If two protocols offer a route to the same network, zebra picks one by **administrative distance** (e.g. OSPF `110` beats iBGP `200`) and installs the winner in the kernel through **netlink** (the interface programs use to read and change the kernel's network settings; the `ip` command uses it too). It also reports interface and address changes back to the daemons, and in EVPN it reports MACs learned by the kernel bridge to `bgpd`.
- **The kernel** forwards packets using the resulting table, the **FIB** (Forwarding Information Base).

Without zebra, the routes learned by the protocols would never reach the kernel, which is why zebra is always started and has no switch in `/etc/frr/daemons`.

How the Dockerfile maps to this:
- The `sed` line switches `bgpd`, `ospfd` and `isisd` to `yes` in `/etc/frr/daemons`.
- The inherited entrypoint starts **watchfrr**, which launches zebra and the enabled daemons and restarts any that crash.
- **vtysh** is the single command line used to configure all daemons together. `touch /etc/frr/vtysh.conf` creates its config file so it starts without a warning.

To see both views on a router: `vtysh -c 'show ip route'` shows zebra's RIB (`O` = OSPF, `C` = connected, `B` = BGP, `>` = selected), and `ip route` shows what ended up in the kernel.

### 3.3 Build Automation: `build.sh`

File: [P1/build.sh](P1/build.sh)

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

It builds and tags the two local images used by every GNS3 template: `host_mchegri:latest` and `routeur_mchegri:latest`.

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
2. **`br0`**: A Linux software bridge acting as a standard Layer 2 switch. By **enslaving** (Linux term for "attaching as a member port", done with `ip link set ... master br0`) both the local host port (`eth1`) and the tunnel port (`vxlan10`) into `br0`, the bridge forwards frames between the physical host and the virtual tunnel based on destination MAC addresses.

### 4.3 Static Unicast Mode (`_s`)

Files: [P2/_mchegri-1_s](P2/_mchegri-1_s) and [P2/_mchegri-2_s](P2/_mchegri-2_s)

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

- `remote 10.1.1.2 local 10.1.1.1`: Explicitly sets the single unicast VTEP peer IP. BUM frames (Broadcast, Unknown unicast, Multicast, e.g. ARP requests) are sent unicast straight to that peer.
- `dstport 4789`: Sets the standard IANA destination port (Linux defaults to non-standard 8472 unless specified).
- **Idempotency**: The initial `ip link del` commands ensure the script can be re-run cleanly without throwing `File exists` errors.

### 4.4 Dynamic Multicast Mode (`_g`)

Files: [P2/_mchegri-1_g](P2/_mchegri-1_g) and [P2/_mchegri-2_g](P2/_mchegri-2_g)

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

- `group 239.1.1.1`: The router joins the multicast group on `eth0` via **IGMP** (Internet Group Management Protocol: how a machine tells the network "send me the traffic of this multicast group"). Broadcast and unknown unicast frames are flooded only to nodes subscribed to `239.1.1.1`.
- When Router 2 replies with unicast traffic, Router 1 records Router 2's MAC in its Forwarding Database (FDB). Subsequent frames are unicast directly.

### 4.5 Host Configuration & Resilient Interface Detection

Files: [P2/_mchegri-1_host](P2/_mchegri-1_host) and [P2/_mchegri-2_host](P2/_mchegri-2_host)

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

### 4.8 Testing Procedure & Verification

All router scripts delete `vxlan10` and `br0` before re-creating them, so you can switch from static to multicast mode by just running the other script. The host scripts only need to run once.

**Step 1: Static mode**
1. Run `_mchegri-1_s` on Router 1 and `_mchegri-2_s` on Router 2.
2. Run `_mchegri-1_host` on Host 1 and `_mchegri-2_host` on Host 2.
3. From Host 1: `ping -c 3 30.1.1.2`

**Step 2: Multicast mode**
1. Run `_mchegri-1_g` on Router 1 and `_mchegri-2_g` on Router 2.
2. From Host 1: `ping -c 3 30.1.1.2`

**On the routers:**
```sh
ip -d link show vxlan10        # VNI 10, dstport 4789, remote 10.1.1.X (static) or group 239.1.1.1 (multicast)
brctl show br0                 # members: eth1 and vxlan10
brctl showmacs br0             # MACs learned by the bridge
bridge fdb show dev vxlan10    # remote MAC -> remote VTEP IP
```

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

The fabric has three layers:

| Layer | Protocol / Feature | Components | Purpose |
| :--- | :--- | :--- | :--- |
| **Underlay** | OSPFv2 Area 0 | All 4 routers | Advertises loopbacks `1.1.1.1`-`1.1.1.4` and the point-to-point links. |
| **Control Plane** | iBGP EVPN (AFI 25 / SAFI 70), AS 1 | Spine (RR) + Leaves | Advertises VNI membership (Type 3) and MAC reachability (Type 2) without data-plane flooding. |
| **Overlay** | VXLAN (VNI 10, UDP 4789) | Leaves (`vxlan10` + `br0`) | Encapsulates tenant Ethernet frames into UDP packets routed over the underlay. |

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

File: [P3/_mchegri-1](P3/_mchegri-1)

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

Files: [P3/_mchegri-2](P3/_mchegri-2), [P3/_mchegri-3](P3/_mchegri-3), [P3/_mchegri-4](P3/_mchegri-4)

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

Files: [P3/_mchegri-1_host](P3/_mchegri-1_host), [P3/_mchegri-2_host](P3/_mchegri-2_host), [P3/_mchegri-3_host](P3/_mchegri-3_host)

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

### 5.8 Testing Procedure & Expected Output

**Step 1: Start the routers and apply their configs.** Run `_mchegri-1` to `_mchegri-4` in their consoles, then wait ~30 seconds for OSPF and BGP to converge.
```sh
# On any leaf (e.g. _mchegri-4): all loopbacks learned via OSPF
vtysh -c 'show ip route'
# O>* 1.1.1.1/32, 1.1.1.2/32, 1.1.1.3/32 via 10.1.1.9, eth2

# On the spine (_mchegri-1): 3 dynamic EVPN sessions
vtysh -c 'show bgp l2vpn evpn summary'
# neighbors 1.1.1.2, 1.1.1.3, 1.1.1.4 marked with * (dynamic)

# Before any host is configured: only Type 3 routes
vtysh -c 'show bgp l2vpn evpn'
# [3]:[0]:[32]:[1.1.1.X] only
```

**Step 2: Start the hosts and watch Type 2 routes appear.** Run `_mchegri-1_host` on Host 1:
```sh
# On Leaf 1 (_mchegri-2) and Leaf 3 (_mchegri-4)
vtysh -c 'show bgp l2vpn evpn'
# a new [2]:[0]:[48]:[<host1-mac>] route appears
```
Then run `_mchegri-2_host` on Host 2 and `_mchegri-3_host` on Host 3.

**Step 3: End-to-end connectivity.** From Host 1:
```sh
ping -c 3 20.1.1.2
ping -c 3 20.1.1.3
```
On the leaves, `bridge fdb show dev vxlan10` lists the remote MACs with `extern_learn` (installed by BGP EVPN) and the destination VTEP IP.

---

## 6. Step-by-Step GNS3 Setup Guide

This section goes from a fresh Kali machine to a working, exported P1 project. Each step lists the exact menu, button, or field to use. Anything not mentioned keeps its default value.

### 6.1 Installing GNS3 & Prerequisites (Kali Linux)

GNS3 has two parts: the **GUI** (`gns3`, the window you click in) and the **server** (`gns3server`, which starts Docker containers and wires the links). The GUI starts the local server automatically. Both are installed with `pipx` into isolated Python environments.

1. **Install pipx and build tools** (to compile `ubridge` later):
   ```sh
   sudo apt update
   sudo apt install -y pipx git build-essential libpcap-dev telnet xterm
   ```
   > Install the apt packages in **one command that only lists packages that exist**. If a single name is unknown (e.g. `ubridge`, `python3-pyqt5.qtwebsockets`), apt aborts and installs **nothing**.

2. **Install the GNS3 server and GUI:**
   ```sh
   pipx install gns3-server
   pipx install gns3-gui
   pipx inject gns3-gui gns3-server PyQt6
   pipx ensurepath
   ```
   - `gns3-gui` 3.x uses **PyQt6**, not PyQt5. Without `PyQt6`, launching `gns3` fails with `No module named 'sip'` / `Can't import Qt modules`.
   - Injecting `gns3-server` into the GUI environment lets the GUI start the local server.

3. **Build and install `ubridge`**, the tool GNS3 uses to create the cables between nodes. Kali has no package for it:
   ```sh
   git clone https://github.com/GNS3/ubridge.git /tmp/ubridge
   cd /tmp/ubridge
   make
   sudo make install          # installs /usr/local/bin/ubridge and sets its network capabilities
   which ubridge              # -> /usr/local/bin/ubridge
   ```

4. **Allow your user to use Docker without `sudo`.** GNS3 runs as your user, so it needs this. Otherwise the Docker page shows `Cannot connect to unix socket /var/run/docker.sock [Permission denied]`.
   ```sh
   sudo usermod -aG docker $USER    # -a = append; never forget it or you lose your other groups (sudo!)
   getent group docker              # must print: docker:x:<gid>:<your-login>
   ```
   Then **log out and log back in** (or reboot). A new group only applies to new login sessions. To test it in the current terminal only, run `newgrp docker`.
   ```sh
   groups | grep docker      # docker must be listed
   docker ps                 # must work WITHOUT sudo
   ```

5. **Build the project images** (§3.3) and check they exist:
   ```sh
   sh P1/build.sh
   docker images | grep mchegri     # host_mchegri and routeur_mchegri
   ```

### 6.2 First Launch & Setup Wizard

1. Start GNS3 from a terminal where `docker ps` works without sudo:
   ```sh
   gns3
   ```
2. The **Setup Wizard** opens on the first launch:
   - Select **Run appliances on my local computer**, then click **Next**.
   - **Local server configuration**: leave everything as is (*Host binding* `127.0.0.1`, *Port* `3080`), then click **Next**.
   - Wait for *Connection to local server successful*, then click **Next**, then **Finish**.
3. If GNS3 asks you to log in (GNS3 3.x controller), use the default account **`admin`** / **`admin`**.
4. A **Project** dialog may open. Click **Cancel** for now; the project is created in §6.4.
5. **Check the console program.** Go to **Edit > Preferences > General**, open the **Console applications** tab, and make sure the telnet command uses a terminal you have installed. The default `xterm -T "{name}" -e "telnet {host} {port}"` works once `xterm` and `telnet` are installed (step 6.1.1). Click **OK**.

### 6.3 Creating the Docker Templates

A *template* is a reusable device model: "a container made from image X, with N network cards". Create one template per image.

**Host template:**

1. In the menu bar, click **Edit > Preferences**.
2. In the left column of the Preferences window, click **Docker containers** (under *Docker*).
3. Click **New** (bottom of the window).
4. **Server type** page: select **Run this Docker container on my local computer**, then click **Next**.
5. **Docker Virtual Machine** page: select **Existing image**. In the **Image list** drop-down, choose **`host_mchegri:latest`**, then click **Next**.
6. **Container name** page: type **`host_mchegri`**, then click **Next**.
7. **Network adapters** page: set **Adapters** to **`2`** (creates `eth0` and `eth1`), then click **Next**.
8. **Start command** page: leave it **empty** so the image's own command is used, then click **Next**.
9. **Console type** page: choose **`telnet`**, then click **Next**.
10. **Environment** page: leave it **empty**, then click **Finish**.

**Router template:** click **New** again and repeat steps 4 to 10 with these values:

| Page | Value |
| :--- | :--- |
| Image list | `routeur_mchegri:latest` |
| Container name | `routeur_mchegri` |
| Adapters | **`4`** (`eth0` to `eth3`, needed by the P3 spine) |
| Start command | *(empty)* |
| Console type | `telnet` |
| Environment | *(empty)* |

Finally, click **Apply**, then **OK** to close Preferences.

> **Fixing a template afterwards** (e.g. adapters left at `1`): go to **Edit > Preferences > Docker containers**, select the template in the list, click **Edit**, open the **General settings** tab, change **Adapters**, then click **OK > Apply > OK**. Nodes already placed in a project keep their old value: delete them and drag them in again.

### 6.4 Building the P1 Topology

1. **Create the project:** click **File > New blank project**. In **Name**, type **`P1`**, keep the default location, and click **OK**.
2. **Show the devices:** in the left toolbar, click the **Browse all devices** icon (the last icon of the vertical toolbar). Docker templates use the *guest* category, so they also appear under **Browse End Devices**.
3. **Place the host:** drag **host_mchegri** from the panel onto the white workspace. GNS3 names it **`host_mchegri-1`** automatically (`{name}-{0}` format).
4. **Place the router:** drag **routeur_mchegri** onto the workspace, next to the host. It is named `routeur_mchegri-1`.
5. **Rename the nodes** (the subject requires the login in every name): right-click a node, click **Change hostname**, type the name, and click **OK**.
   - Host: `host_mchegri-1`
   - Router: `routeur_mchegri`
6. **Draw the cable:**
   - In the left toolbar, click **Add a link** (the cable icon at the bottom). The cursor becomes a cross.
   - Click the **host**. A list of its ports appears; click **`eth0`**.
   - Click the **router**, then click **`eth0`**.
   - Click **Add a link** again (or press `Esc`) to leave link mode.
7. **Start the nodes:** in the top toolbar, click the green **▶ Start/Resume all nodes** button and confirm with **Yes**. Both nodes and the link ends turn **green**.
8. **Save:** **File > Save project** (`Ctrl+S`).

### 6.5 Verifying P1

Open a console on each node: **right-click the node > Console**, or **double-click** it. An `xterm` window opens with a shell inside the container.

**On `routeur_mchegri`:**
```sh
vtysh -c 'show daemons'   # must list: zebra bgpd ospfd isisd (+ mgmtd staticd watchfrr)
ps                        # the FRR daemons are running
ip addr                   # lo = 127.0.0.1 only; eth0..eth3 have NO IP address
```

**On `host_mchegri-1`:**
```sh
which busybox ip ifconfig ping    # all four are found
ip addr                           # lo = 127.0.0.1 only; eth0 and eth1 have NO IP address
```

> Outside GNS3 (`docker run`), `eth0` gets a `172.17.x.x` address from Docker's own bridge. Inside GNS3 the containers have **no** IP by default. That is the expected P1 result.

To stop: click the red **■ Stop all nodes** button in the top toolbar.

### 6.6 Building the P2 & P3 Topologies

1. Create one new blank project per part (**File > New blank project**: `P2`, `P3`), exactly as in §6.4.
2. Drag devices onto the workspace and **rename them using the login `mchegri`**:
   - P1: `host_mchegri-1`, `routeur_mchegri`
   - P2: `host_mchegri-1`, `routeur_mchegri-1`, `Switch_mchegri`, `routeur_mchegri-2`, `host_mchegri-2`. The switch is the built-in **Ethernet switch** from **Browse Switches**.
   - P3: `_mchegri-1` (spine), `_mchegri-2/3/4` (leaves), `host_mchegri-1/2/3`
3. Wire links strictly according to the cabling tables (see §4.1 for P2 and §5.1 for P3). With **Add a link**, pick the exact `ethX` port listed in the table each time.
4. Start all nodes (**▶ Start/Resume all nodes**).

### 6.7 Applying Configurations

Double-click each node to open its telnet terminal and paste the script contents, or use Docker CLI from the host terminal:

```sh
# Example: copying config script into a running GNS3 container
docker ps --format '{{.Names}}'
docker cp P3/_mchegri-1 <container-name>:/tmp/conf.sh
docker exec -it <container-name> sh /tmp/conf.sh
```

### 6.8 Exporting Portable Projects (`.gns3project`)

1. With the project open (and saved), click **File > Export portable project**.
2. In the export window, tick **Include base images**. Leave the other options (*Include snapshots*, *Reset MAC addresses*, compression) at their defaults, then click **Next** (or **Export**).
3. In the file dialog, browse to the part's folder in this repository and name the file after the part:
   - `P1/P1.gns3project`
   - `P2/P2.gns3project`
   - `P3/P3.gns3project`
4. Click **Save** and wait for the progress bar to finish.
5. Check the archive and commit it:
   ```sh
   file P1/P1.gns3project     # -> Zip archive data
   git add P1/P1.gns3project
   ```

> [!IMPORTANT]
> The subject strictly requires these portable archives, exported with **Include base images**, to be present in the git repository.

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
| `gns3`: `No module named 'sip'` / `Can't import Qt modules` | GNS3 GUI 3.x needs PyQt6, not PyQt5 | `pipx runpip gns3-gui list \| grep -i qt` | `pipx inject gns3-gui PyQt6` (§6.1). |
| `apt`: `Unable to locate package ubridge` (and nothing installed) | `ubridge` is not packaged on Kali; one unknown name aborts the whole `apt install` | `which ubridge` | Build it from source (§6.1 step 3) and re-run `apt install` without the unknown names. |
| GNS3 Docker page: `Cannot connect to unix socket /var/run/docker.sock [Permission denied]` | User not in the `docker` group, or group not applied yet | `getent group docker`, `docker ps` | `sudo usermod -aG docker $USER`, log out/in, restart `gns3` (§6.1 step 4). |
| `Cannot find device "eth1"` on the host in GNS3 | Host template created with 1 adapter | `ip link` inside node | Edit the template, set **Adapters** to `2` (§6.3), then re-drag the node. |
| Double-click on a node opens nothing | Console program missing | `which xterm telnet` | `sudo apt install xterm telnet`, or change **Edit > Preferences > General > Console applications**. |
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
   - Open [P1/_mchegri-1_host](P1/_mchegri-1_host) and [P1/_mchegri-2](P1/_mchegri-2), explaining each line.
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

---

## 11. Glossary

Short definitions of every technical term used in this manual, in alphabetical order. The section where the term is explained in more detail is given in brackets.

| Term | Meaning |
| :--- | :--- |
| **Address family (AFI / SAFI)** | A kind of route carried by MP-BGP, named by two numbers. L2VPN EVPN = AFI 25 / SAFI 70. (§2.3) |
| **Administrative distance** | Preference zebra gives to each routing source when two offer the same route; lower wins (connected 0, OSPF 110, iBGP 200). (§3.2) |
| **ARP** | Address Resolution Protocol: broadcasts "who has IP X? tell me your MAC". (§1.1) |
| **AS (Autonomous System)** | A network run by one organization under one routing policy, identified by a number. This project uses AS 1. (§2.2) |
| **BGP / iBGP / eBGP** | Border Gateway Protocol, the Internet's routing protocol, over TCP 179. iBGP = between routers of the same AS, eBGP = between different ASes. (§2.3) |
| **Bridge** | A switch implemented in software inside the Linux kernel (`br0`). (§4.2) |
| **Broadcast domain** | The set of machines that receive a frame sent to everyone. (§1.1) |
| **BUM traffic** | Broadcast, Unknown unicast and Multicast frames, which must reach every member of an L2 network. (§2.4) |
| **Clos / spine-leaf** | Two-layer fabric: every leaf (where hosts connect) is cabled to every spine (core). (§1.3, §5.1) |
| **Container / image** | A container is an isolated program sharing the host kernel; an image is the read-only template it starts from. (§1.3) |
| **Control plane / data plane** | Control plane decides where traffic goes (OSPF, BGP); data plane actually moves the packets. (§1.2) |
| **Daemon** | A program that runs in the background (e.g. `bgpd`, `zebra`). (§1.3) |
| **ECMP** | Equal-Cost Multi-Path: traffic is spread over several paths of equal cost. (§1.2) |
| **Encapsulation** | Wrapping a whole frame or packet inside another one, as its payload. (§1.2, §2.1) |
| **EVPN** | Ethernet VPN: BGP extension that advertises MAC addresses and VNIs instead of IP routes. (§2.4) |
| **Ethernet frame** | The L2 unit of data: destination MAC, source MAC, payload. (§1.1) |
| **FDB** | Forwarding Database: a bridge's table of "MAC X is behind port Y". (§2.4) |
| **FIB / RIB** | RIB = all routes known by zebra; FIB = the selected routes installed in the kernel and used to forward. (§3.2) |
| **Flood-and-learn** | Sending a frame for an unknown MAC to everybody, then remembering where the reply came from. (§1.2) |
| **Fragmentation** | Splitting a packet that is bigger than the MTU into several pieces. (§2.1) |
| **FRRouting (FRR)** | Open-source routing suite, maintained fork of Quagga. (§3.2) |
| **Full mesh** | Every router peering with every other router. (§2.5) |
| **GNS3** | Graphical Network Simulator 3: draws a topology and runs virtual devices. (Intro, §6) |
| **Header** | Control information a protocol layer adds in front of the data. (§2.1) |
| **IGMP** | Internet Group Management Protocol: how a machine joins a multicast group. (§4.4) |
| **IGP** | Interior Gateway Protocol: a routing protocol used inside one AS (OSPF, IS-IS). (§2.2) |
| **IMET (EVPN Type 3)** | Inclusive Multicast Ethernet Tag route: "I am a VTEP in VNI 10, send me BUM traffic". (§2.4, §5.5) |
| **IS-IS** | Link-state IGP like OSPF, designed by ISO, carried directly in L2 frames. (§2.6) |
| **Jumbo frame** | An Ethernet frame bigger than the standard 1500-byte MTU. (§2.1) |
| **Kernel** | The core of the operating system; on Linux it forwards packets and runs bridges and VXLAN interfaces. (§3.2) |
| **Layer 2 (L2) / Layer 3 (L3) / Layer 4 (L4)** | OSI layers: L2 data link (MAC, switches), L3 network (IP, routers), L4 transport (TCP, UDP). (§1.1, §2.1) |
| **Link-state** | Routing method where every router learns the full network map (LSDB) and computes paths itself. (§2.2) |
| **Loopback** | Virtual interface that is always up; its /32 address is the router's stable identity. (§1.5) |
| **LSA / LSDB** | OSPF Link-State Advertisement / Link-State Database (the network map built from LSAs). (§2.2) |
| **MAC address** | Hardware address of a network card, used at L2. (§1.1) |
| **MAC/IP route (EVPN Type 2)** | "Host MAC X is behind VTEP Y". (§2.4, §5.5) |
| **MP-BGP** | Multiprotocol BGP: one session carries several address families. (§2.3) |
| **MTU** | Maximum Transmission Unit: biggest packet an interface sends in one piece (1500 bytes on Ethernet). (§2.1) |
| **Netlink** | Interface programs use to read and change the kernel's network settings. (§3.2) |
| **NLRI** | Network Layer Reachability Information: the routes carried inside a BGP update. (§2.3) |
| **OSI model** | 7-layer reference model of networking. (§2.1) |
| **OSPF / Area 0** | Open Shortest Path First, a link-state IGP. Area 0 is its backbone area. (§2.2) |
| **Overlay / underlay** | Underlay = real network of cables and routers; overlay = virtual network built on top of it. (§1.2) |
| **Peer / session** | Two BGP routers that talk to each other / their TCP conversation. (§2.3) |
| **Peer group** | Named set of BGP neighbors sharing the same settings. (§2.5) |
| **Point-to-point link** | A cable between exactly two routers, usually a /30. (§1.5) |
| **Prefix length (/24, /30, /32)** | Number of leading address bits that form the network part. (§1.5) |
| **Quagga** | Older routing suite, predecessor of FRR. (§3.2) |
| **RFC** | Numbered Internet standard document. (§2.2) |
| **Route Reflector (RR)** | iBGP router that relays routes between its clients, so they don't need a full mesh. (§2.5) |
| **Split horizon (iBGP)** | Rule that an iBGP router never re-advertises a route learned from another iBGP peer. (§2.3) |
| **STP** | Spanning Tree Protocol: blocks links to prevent L2 loops. (§1.1) |
| **Subnet** | A range of IP addresses, e.g. `30.1.1.0/24`. (§1.1) |
| **Switch** | L2 device that forwards frames by MAC address. (§1.1) |
| **TCP / UDP** | L4 transport protocols: TCP is reliable and connection-based; UDP is simple and connectionless. (§1.2, §2.1) |
| **Tenant** | One customer of a shared data center. (§1.1) |
| **Unicast / multicast / broadcast** | Sent to one destination / to a group that receivers join / to everyone on the L2 network. (§1.3) |
| **VLAN** | Virtual LAN: isolated L2 network identified by a 12-bit tag (IEEE 802.1Q). (§1.1) |
| **VNI** | VXLAN Network Identifier: 24-bit ID of a virtual L2 network. (§1.2) |
| **VTEP** | VXLAN Tunnel End Point: the device that wraps and unwraps VXLAN packets. (§1.3) |
| **VXLAN** | Virtual eXtensible LAN: carries Ethernet frames inside UDP port 4789. (§1.2, §2.1) |
| **watchfrr / vtysh** | watchfrr starts and restarts the FRR daemons; vtysh is the single CLI that configures them. (§3.2) |
| **zebra** | Core FRR daemon: collects routes from the protocol daemons and installs the best ones in the kernel. (§3.2) |
