# BADASS notes

Notes on the project: the protocols, what each config line does, the commands, how to test, and the questions that come up at the defense. Written so someone with basic networking (IP, subnets, a terminal) can follow.

## Table of contents

- [0. Conventions](#0-conventions)
- [1. Overview](#1-overview)
- [2. Networking basics](#2-networking-basics)
- [3. Tools](#3-tools)
- [4. Protocols](#4-protocols)
- [5. Part 1: Docker images and GNS3](#5-part-1-docker-images-and-gns3)
- [6. Part 2: VXLAN (static and multicast)](#6-part-2-vxlan-static-and-multicast)
- [7. Part 3: BGP EVPN with a route reflector](#7-part-3-bgp-evpn-with-a-route-reflector)
- [8. Running it in GNS3](#8-running-it-in-gns3)
- [9. Commands](#9-commands)
- [10. Troubleshooting](#10-troubleshooting)
- [11. Defense](#11-defense)
- [12. Glossary](#12-glossary)
- [13. Submission checklist](#13-submission-checklist)
- [14. Resources](#14-resources)

---

## 0. Conventions

- `$` means a command run in a shell (on a router or host container).
- `vtysh -c "..."` runs one FRR command from a normal shell. Typing `vtysh` alone opens the interactive FRR shell.
- The 42 subject uses the login `wil` in its examples. This repo uses **`mchegri`**: `_wil-1` in the subject means `_mchegri-1` here.

---

## 1. Overview

### 1.1 What we build

We simulate a small **data center network** on one computer and build it up in three steps:

| Part | Folder | What it does | Key ideas |
| :-- | :-- | :-- | :-- |
| **P1** | [P1/](P1/) | Two Docker images: a **host** (a plain Linux machine) and a **router** (Linux + FRRouting) | Docker, GNS3, FRR daemons |
| **P2** | [P2/](P2/) | Two hosts on **one virtual LAN (VXLAN 10)** even though a routed network separates them | VXLAN, Linux bridge, static and multicast tunnel endpoints |
| **P3** | [P3/](P3/) | A **spine-leaf fabric**: 1 spine + 3 leaves + 3 hosts. Leaves learn where every MAC address lives through **BGP EVPN**, with no flooding guesswork | OSPF, iBGP, route reflector, EVPN route types 2 and 3 |

### 1.2 Why

Cloud providers run millions of virtual machines that belong to many customers (tenants). Each tenant wants a private
LAN, and a VM must keep its IP and MAC address when it moves to another rack. Classic Ethernet (VLANs) cannot do this at scale:

- A VLAN ID is 12 bits, so you get only **4,094 usable networks**.
- Large Layer-2 networks need **Spanning Tree**, which blocks redundant links and so wastes bandwidth.
- Broadcast traffic (ARP) **floods everywhere**.

The modern answer, which is exactly this project:

1. Build a simple, robust **routed IP network** (the *underlay*). Here we use **OSPF**.
2. Carry tenant Ethernet frames *inside* UDP packets across it (the *overlay*). Here we use **VXLAN**, with 16 million IDs.
3. Use a **control plane** so every switch already knows where each MAC address is, instead of flooding to discover it. Here we use **BGP EVPN**.

### 1.3 Repository map

```
bgp/
├── README.md              short overview
├── MANUAL.md              these notes
├── en.subject.pdf         The official 42 subject
├── P1/
│   ├── _mchegri-1_host    Dockerfile - host image (Alpine + busybox + net tools)
│   ├── _mchegri-2         Dockerfile - router image (FRRouting 9.1.3 + tcpdump)
│   ├── build.sh           Builds both images with the tags used everywhere
│   └── README.md
├── P2/
│   ├── _mchegri-1_s / _mchegri-2_s     Router 1 / 2 - VXLAN static (unicast)
│   ├── _mchegri-1_g / _mchegri-2_g     Router 1 / 2 - VXLAN multicast group
│   ├── _mchegri-1_host / _mchegri-2_host  Host IP config (30.1.1.x/24)
│   └── README.md
└── P3/
    ├── _mchegri-1         Spine / route reflector (OSPF + BGP RR)
    ├── _mchegri-2/3/4     Leaves / VTEPs (OSPF + BGP EVPN + VXLAN 10)
    ├── _mchegri-1/2/3_host  Host IP config (20.1.1.x/24)
    └── README.md
```

Note on file names: the subject requires the exact pattern `_<login>-N`, `_<login>-N_host`, `_<login>-N_s`, `_<login>-N_g`.
The files in P2 and P3 are **shell scripts** that you run inside the matching device. The files in P1 are **Dockerfiles**.

---

## 2. Networking basics

### 2.1 Layers

Networks are built in layers. Each layer wraps (*encapsulates*) the data from the layer above with its own header.

| Layer | Name | Address used | Device that works here | In this project |
| :-- | :-- | :-- | :-- | :-- |
| L2 | Data link (Ethernet) | **MAC address** (`aa:bb:cc:dd:ee:ff`) | Switch / bridge | `br0`, the GNS3 switch, host-to-host frames |
| L3 | Network (IP) | **IP address** (`10.1.1.1`) | Router | OSPF routes, VTEP loopbacks |
| L4 | Transport (TCP/UDP) | **Port** (`179`, `4789`) | - | BGP uses TCP 179, VXLAN uses UDP 4789 |
| L7 | Application | - | - | BGP messages, ping (ICMP sits at L3) |

**Encapsulation** example, for a ping from host 1:

```
[ Ethernet hdr | IP hdr | ICMP echo request ]
   L2 (MACs)    L3 (IPs)  payload
```

VXLAN takes this **whole frame** and puts it inside another IP/UDP packet (see §4.1). That idea is the core of the project.

### 2.2 MAC vs IP, switch vs router

- **MAC address**: a 48-bit hardware identity, used only *inside one LAN* (one broadcast domain).
- **IP address**: a logical address that routers use to move packets *between* networks.
- **Switch / bridge (L2)**: forwards frames by **destination MAC**. It learns which port each MAC lives on by
  looking at the **source MAC** of incoming frames and stores that in the **FDB** (Forwarding DataBase, the MAC table).
  If it does not know a destination, it **floods** the frame to all ports.
- **Router (L3)**: forwards packets by **destination IP**, using its **routing table**. It never forwards broadcasts.

### 2.3 ARP (how a host finds a MAC)

Host 1 (`20.1.1.1`) wants to ping `20.1.1.2`, which is on the same subnet. It needs that host's MAC, so it sends:

```
ARP request  (broadcast, dst MAC ff:ff:ff:ff:ff:ff): "Who has 20.1.1.2? Tell 20.1.1.1"
ARP reply    (unicast):                              "20.1.1.2 is at 62:b7:1f:a6:5a:34"
```

Broadcasts like this are the **BUM** traffic (Broadcast, Unknown unicast, Multicast) that VXLAN must carry somehow. P2 and P3 solve this in different ways.

### 2.4 Subnets and CIDR (`/24`, `/30`, `/32`)

The number after `/` is how many bits are the **network** part. The remaining bits identify hosts.

| Prefix | Addresses | Usable hosts | Used in this repo for |
| :-- | :-- | :-- | :-- |
| `/24` | 256 | 254 | Host LANs: `30.1.1.0/24` (P2), `20.1.1.0/24` (P3), P2 underlay `10.1.1.0/24` |
| `/30` | 4 | 2 | P3 point-to-point router links (one IP per side) |
| `/29` | 8 | - | P3 BGP `listen range 1.1.1.0/29` (covers `1.1.1.0`-`1.1.1.7`) |
| `/32` | 1 | 1 | **Loopback** addresses `1.1.1.X/32` (router identity) |

P3's `/30` links:

| Link | Network | Spine side | Leaf side |
| :-- | :-- | :-- | :-- |
| Spine <-> Leaf 1 (`_mchegri-2`) | `10.1.1.0/30` | `.1` | `.2` |
| Spine <-> Leaf 2 (`_mchegri-3`) | `10.1.1.4/30` | `.5` | `.6` |
| Spine <-> Leaf 3 (`_mchegri-4`) | `10.1.1.8/30` | `.9` | `.10` |

(In `10.1.1.0/30`, `.0` is the network address and `.3` is broadcast, which leaves `.1` and `.2` usable.)

**Why loopbacks?** A loopback interface (`lo`) is virtual and **never goes down**, unlike a cable. Giving each router a stable
`/32` on `lo` provides one permanent identity for BGP sessions and VXLAN tunnels, whichever physical link carries the traffic.

### 2.5 Unicast, broadcast, multicast

| Type | Goes to | Example in project |
| :-- | :-- | :-- |
| Unicast | One receiver | VXLAN static mode (`remote 10.1.1.2`), BGP sessions |
| Broadcast | Everyone in the LAN | ARP requests from hosts |
| Multicast | Everyone who **joined a group** | VXLAN group `239.1.1.1` (P2 `_g`), OSPF hellos to `224.0.0.5` |

Multicast addresses are in `224.0.0.0/4`. `239.0.0.0/8` is "administratively scoped" (private use), which is why `239.1.1.1` is used.
Receivers join a group using **IGMP**.

### 2.6 Control plane vs data plane

- **Data plane**: actually moving packets (encapsulate, look up, forward). It is done by the **Linux kernel** here.
- **Control plane**: deciding *where* packets should go (exchanging routes, MACs). It is done by **FRR daemons** here (OSPF, BGP).

P2 has **no control plane** for MACs: the data plane learns by flooding. P3 adds one (BGP EVPN). That difference is the main lesson of the project.

---

## 3. Tools

### 3.1 Virtual machine

The subject requires that **everything runs inside a VM** (for example Ubuntu/Debian in VirtualBox, UTM or VMware).
GNS3 and Docker are installed inside it. Reason: the evaluation happens on your machine, and the VM gives a reproducible environment.

### 3.2 Docker

Docker runs **containers**: lightweight isolated Linux environments that share the host kernel.

| Concept | Meaning |
| :-- | :-- |
| **Image** | A read-only template (filesystem + metadata), built from a **Dockerfile** |
| **Container** | A running instance of an image |
| `FROM` | Base image to start from |
| `RUN` | Execute a command at build time (installs packages, edits files) |
| `docker build -t NAME -f FILE .` | Build an image named NAME from Dockerfile FILE |
| **Network namespace** | Each container has its own interfaces, routes and ARP table. This is why each container behaves like a separate machine |

Important: every container has **its own network stack**, but they all share **one kernel**. VXLAN, bridges and routing
all come from the Linux kernel, so containers make perfect lightweight routers.

### 3.3 GNS3

**GNS3** (Graphical Network Simulator 3) is a GUI where you drag devices (Docker containers, switches, VMs) onto a canvas and
draw cables between them. GNS3 creates the virtual cables (via `ubridge`) and gives you a **console** (telnet) for each device.

Used for:
- Building the topologies of P1, P2 and P3 visually.
- Opening consoles to configure devices.
- **Capturing packets** on any link with Wireshark (right-click a link -> *Start capture*).
- **Exporting** each part as a `.gns3project` ZIP (required deliverable).

The P2 *switch* (`Switch_mchegri`) is GNS3's built-in **Ethernet switch** node. It is not a Docker container.

### 3.4 Alpine Linux and BusyBox

- **Alpine Linux**: a tiny (~5 MB) Linux distribution. Package manager: `apk` (`apk add <pkg>`).
- **BusyBox**: a single binary that provides hundreds of Unix commands (`sh`, `ls`, `ping`, `ip`, `ifconfig`...). The subject requires it on both images.

Extra packages in the host image ([P1/_mchegri-1_host](P1/_mchegri-1_host)):

| Package | Gives you | Why |
| :-- | :-- | :-- |
| `busybox` | basic Unix tools | Required by the subject |
| `iproute2` | full `ip` command (`ip addr`, `ip link`, `ip route`) | Configure interfaces |
| `net-tools` | `ifconfig`, `netstat`, `route` | Classic tools, familiar to evaluators |
| `iputils` | full `ping` | Connectivity tests |

### 3.5 FRRouting (FRR)

**FRR** is an open-source routing suite, a maintained fork of **Quagga** (which forked from **Zebra**). It turns a Linux box into a
real router that speaks OSPF, BGP, IS-IS and more. We use the official image `quay.io/frrouting/frr:9.1.3`.

FRR is a set of cooperating **daemons** (background processes):

| Daemon | Role |
| :-- | :-- |
| **zebra** | The core. It collects routes from all protocol daemons, picks the best ones and **installs them in the Linux kernel**. It also watches kernel interfaces, the bridge FDB and VXLAN devices (this is how EVPN learns local MACs) |
| **bgpd** | BGP protocol (P3: iBGP + EVPN) |
| **ospfd** | OSPFv2 protocol (P3: underlay) |
| **isisd** | IS-IS protocol (required by the subject to be *present*; not configured in our topologies) |
| **watchfrr** | Supervisor that starts the daemons and restarts them if they crash |
| **staticd**, **mgmtd** | Always started by FRR 9 (static routes, management) |

Key files and tools inside the router container:

| Item | Purpose |
| :-- | :-- |
| `/etc/frr/daemons` | Which daemons start (`bgpd=yes`, `ospfd=yes`...). Our Dockerfile edits this |
| `/etc/frr/frr.conf` | Saved configuration (written by `write memory`) |
| `/etc/frr/vtysh.conf` | Settings for `vtysh`. We create it empty to avoid a startup warning |
| `vtysh` | **The FRR shell.** One CLI that talks to all daemons. Cisco-like syntax |
| `/usr/lib/frr/docker-start` | Image entrypoint. Runs `watchfrr` in the foreground so the container stays alive |

`vtysh` modes (as on a Cisco router):

```
router#                       ← "enable" mode: show commands
router# configure terminal
router(config)#               ← global config
router(config)# router ospf
router(config-router)#        ← protocol config
router(config-router)# address-family l2vpn evpn
router(config-router-af)#     ← address-family config (BGP)
... exit / end / write memory
```

### 3.6 Linux networking primitives

Our routers' data plane is plain Linux kernel networking, configured with `ip` (from iproute2) and `brctl` (bridge-utils).

| Object | Created with | What it is |
| :-- | :-- | :-- |
| Physical-like interface (`eth0`, `eth1`...) | GNS3 / `veth` | A port of the device, wired by GNS3 |
| Loopback (`lo`) | always exists | Virtual interface that never goes down. We put `1.1.1.X/32` on it |
| **Bridge** (`br0`) | `ip link add br0 type bridge` | A software L2 switch inside the router. It learns MACs and floods unknowns |
| **VXLAN device** (`vxlan10`) | `ip link add vxlan10 type vxlan id 10 ...` | A virtual port: frames sent into it are encapsulated in UDP/4789 and sent to a remote VTEP; received VXLAN packets come out of it as frames |
| **veth pair** | `ip link add a type veth peer name b` | A virtual cable with two ends |
| Network namespace | Docker / `nsenter` | Isolated network stack (one per container) |

The trick that makes a router a **VTEP**: put the host-facing interface **and** `vxlan10` in the same bridge `br0`:

```
          router (VTEP)
 host ── eth1 ─┐
               ├── br0  (L2 switch)
     vxlan10 ──┘
        │  encapsulate / decapsulate
        ▼
   UDP 4789 over eth0 (underlay)  ──►  remote VTEP
```

The bridge then does normal switching between a real port (`eth1`) and a "tunnel port" (`vxlan10`).

### 3.7 Packet capture: tcpdump and Wireshark

- **tcpdump** (installed in the router image): command-line capture. Example: `tcpdump -ni eth0 udp port 4789`.
- **Wireshark**: GUI capture. GNS3 launches it when you capture a link. Wireshark decodes VXLAN automatically on UDP 4789 and shows the outer **and** inner headers.

---

## 4. Protocols

### 4.1 VXLAN: Virtual eXtensible LAN (RFC 7348)

**Problem:** we want hosts in different places to be in the *same L2 LAN*, but only a routed IP network connects them.

**Solution:** "MAC-in-UDP". Wrap the entire Ethernet frame in a UDP packet and send it across the IP network to the
device in front of the destination host. That device unwraps it and delivers the original frame.

```
 ┌────────────── Outer (underlay) ───────────────┐┌──────── Inner (overlay, untouched) ───────┐
 │ Outer Eth │ Outer IP          │ UDP     │VXLAN││ Inner Eth          │ Inner IP │ ICMP...  │
 │ 14 B      │ 20 B              │ 8 B     │ 8 B ││ host MACs          │ 20.1.1.x │          │
 │           │ src/dst = VTEP IPs│ dst 4789│VNI10││                    │          │          │
 └───────────────────────────────────────────────┘└───────────────────────────────────────────┘
                     50 bytes of overhead
```

The VXLAN header (8 bytes): `Flags(8 bits, I-flag=1) | Reserved(24) | VNI(24) | Reserved(8)`.

| Term | Meaning |
| :-- | :-- |
| **VNI** | VXLAN Network Identifier. 24 bits, so ~16.7 million segments. Like a VLAN ID, but much larger. We use **VNI 10** |
| **VTEP** | VXLAN Tunnel End Point. The device that encapsulates and decapsulates. Our routers in P2 and the **leaves** in P3 |
| **UDP 4789** | IANA-assigned VXLAN port. Linux's historic default is 8472, so we set `dstport 4789` explicitly |
| **Underlay** | The IP network that carries the UDP packets. It doesn't care what is inside |
| **Overlay** | The virtual L2 network seen by the hosts |

**The BUM problem.** When host 1 sends an ARP broadcast, which remote VTEP(s) should get it? VXLAN alone does not say.
There are three answers, and the project shows all of them:

| Method | Where | How BUM is delivered | How remote MACs are learned |
| :-- | :-- | :-- | :-- |
| **Static unicast** | P2 `_s` | Sent to the hard-coded `remote` IP | Data plane: bridge learns from received frames |
| **Multicast group** | P2 `_g` | Sent to multicast group `239.1.1.1`; every VTEP that joined gets it | Data plane: flood-and-learn |
| **EVPN (head-end replication)** | P3 | The VTEP sends one unicast copy to **each** VTEP that announced VNI 10 (EVPN type 3) | **Control plane: BGP EVPN type 2** (`nolearning`) |

**MTU note:** the 50-byte overhead means a 1500-byte inner frame becomes 1550 bytes outside. When `vxlan10` is created with
`dev eth0` (P2), Linux sets its MTU to 1450 automatically. In P3 no `dev` is given. Pings use small packets, so this
doesn't affect the project, but in production you raise the underlay MTU (for example 9000, "jumbo frames").

### 4.2 OSPF: Open Shortest Path First (RFC 2328)

**Role in P3:** the **underlay routing protocol**. Its only job is to let every router reach every other router's loopback
(`1.1.1.1`-`1.1.1.4`), because BGP sessions and VXLAN tunnels are built between loopbacks.

How it works, simply:

1. **Neighbor discovery:** each router sends **Hello** packets on its OSPF interfaces to multicast `224.0.0.5` (IP protocol 89, not TCP/UDP) every 10 s.
   Routers with matching parameters (area, timers, subnet) become **neighbors**, and then **Full** adjacencies.
2. **Flooding the map:** each router describes its links in **LSAs** (Link-State Advertisements). Every router in the area gets every LSA,
   so all routers share the same **link-state database** (a map of the network).
3. **Computing paths:** each router runs **Dijkstra's shortest-path-first** algorithm on that map and installs the best routes in the kernel through zebra.

| OSPF concept | Value in P3 |
| :-- | :-- |
| Type | **IGP** (Interior Gateway Protocol): routing *inside* one organization |
| Area | Everything in **area 0** (the backbone) |
| Router ID | Set to the loopback (`1.1.1.X`) |
| `network X area 0` | "Enable OSPF on interfaces whose IP falls in X, and advertise X." |
| Administrative distance | 110 (FRR) |
| Neighbor states | Down -> Init -> 2-Way -> ExStart -> Exchange -> Loading -> **Full** |

**Why OSPF and not BGP for the underlay?** The subject requires OSPF (to keep evaluation simple). OSPF also discovers neighbors automatically
and converges fast. BGP underlays (RFC 7938) exist in very large fabrics, but they add complexity.

### 4.3 BGP: Border Gateway Protocol (RFC 4271)

**BGP is the routing protocol of the Internet.** It exchanges reachability between **Autonomous Systems** (AS). An AS is a network under one administration, identified by an AS number.

| BGP fact | Detail |
| :-- | :-- |
| Transport | **TCP port 179**. Peers must already be able to reach each other, which OSPF provides |
| Neighbors | Configured explicitly (`neighbor X remote-as N`) or dynamically (`bgp listen range`) |
| Path-vector | Routes carry attributes (AS_PATH, NEXT_HOP, LOCAL_PREF, communities...) used to choose the best path |
| **eBGP** | Peers in **different** AS (Internet use). Administrative distance 20 |
| **iBGP** | Peers in the **same** AS (our case: everyone is in **AS 1**). Administrative distance 200 |
| Session states | Idle -> Connect -> Active -> OpenSent -> OpenConfirm -> **Established** |
| Messages | OPEN, UPDATE (routes), KEEPALIVE (every 60 s by default), NOTIFICATION (error) |

`update-source lo`: by default BGP uses the outgoing interface IP as the session source. We force the **loopback** so the session
is between stable `1.1.1.X` addresses and survives link changes.

> AS 1 is technically a public AS number. In a closed lab it doesn't matter. Real private networks use 64512-65534.

### 4.4 MP-BGP: Multiprotocol BGP (RFC 4760)

Original BGP only carried IPv4 prefixes. **MP-BGP** adds **address families** (AFI/SAFI), so the same BGP session can carry other kinds
of information: IPv6, VPNs and, in our case, **`l2vpn evpn`** (AFI 25 / SAFI 70). That is why our config has:

```
address-family l2vpn evpn
 neighbor ... activate
```

`activate` means "exchange EVPN routes with this neighbor". Without it, the session comes up but carries no EVPN routes.

### 4.5 Route reflection (RFC 4456)

**The iBGP rule (split horizon):** a router must **not** pass a route learned from one iBGP peer to another iBGP peer. This prevents loops,
since iBGP doesn't change AS_PATH. Consequence: normally every iBGP router must peer with every other one (**full mesh**), which needs
`n(n-1)/2` sessions: 3 sessions for 3 leaves, 4,950 for 100.

**Route Reflector (RR):** one router (our **spine**, `_mchegri-1`) is allowed to **reflect** routes between its **clients** (the leaves).
Each leaf needs only **one** session, to the RR.

```
Full mesh (no RR):              With RR (P3):
 L1 ─── L2                         RR (1.1.1.1)
  \    /                          /   |   \
   \  /                         L1    L2   L3
    L3
```

Important: the RR is only in the **control plane**. It reflects routes, but it is **not** a VTEP: it has no `vxlan10` and no bridge.
In the data plane, the spine is just an IP router that forwards UDP/4789 packets between leaves without looking inside.

**Dynamic neighbors** (`bgp listen range 1.1.1.0/29 peer-group ibgp`): the RR accepts a BGP session from **any** address in `1.1.1.0/29`
and applies the `ibgp` peer-group settings to it. Leaves are not listed one by one on the RR. This matches the subject's "*leaves configured to have dynamic relationships*".
A new leaf with loopback `1.1.1.5` would be accepted with zero change on the spine.

### 4.6 EVPN: Ethernet VPN (RFC 7432, and RFC 8365 for VXLAN)

**EVPN** is an MP-BGP address family that carries **L2 information**: which MAC (and optionally IP) is behind which VTEP, and which VTEPs
are in which VNI. It replaces "flood and learn" with "advertise and know".

The subject says "*without using MPLS*". EVPN was first defined for MPLS networks. RFC 8365 defines EVPN with a VXLAN data plane, which is what we use.

**EVPN route types** (the "Type" number shows as `[2]` / `[3]` in FRR output):

| Type | Name | Meaning in plain words | Used here |
| :-- | :-- | :-- | :-- |
| 1 | Ethernet Auto-Discovery | Multihoming (one host connected to two leaves) | No |
| **2** | **MAC/IP Advertisement** | "MAC `aa:bb..` (and maybe IP `x`) is behind me, VTEP `1.1.1.2`, in VNI 10" | **Yes**: appears when a host becomes active |
| **3** | **Inclusive Multicast Ethernet Tag (IMET)** | "I, VTEP `1.1.1.2`, take part in VNI 10. Send me copies of BUM traffic." | **Yes**: appears as soon as a leaf comes up, before any host exists |
| 4 | Ethernet Segment | Multihoming designated forwarder election | No |
| 5 | IP Prefix | L3 routing between subnets (symmetric IRB) | No |

How FRR shows them:

```
Route [3]:[0]:[32]:[1.1.1.2]                  ← type 3, ethernet tag 0, 32-bit IP = VTEP 1.1.1.2
Route [2]:[0]:[48]:[aa:bb:cc:dd:ee:ff]        ← type 2, ethernet tag 0, 48-bit MAC
Route [2]:[0]:[48]:[aa:bb:..]:[32]:[20.1.1.1] ← type 2 with an IP too (only if the VTEP learns the host IP)
```

In this project the leaves have no IP on `br0` (no SVI), so they normally learn **MAC-only** type-2 routes. That explains the subject's remark "*without assigning an IP address our VTEP automatically discovers the MAC address*": the MAC is learned as soon as the host sends **any** frame (for example an IPv6 neighbor solicitation sent automatically when the interface comes up).

**RD and RT** (you'll see them in `show bgp l2vpn evpn`):

| | Name | Purpose | Value here (auto-derived by FRR) |
| :-- | :-- | :-- | :-- |
| **RD** | Route Distinguisher | Makes routes from different VTEPs/VNIs unique in BGP | `<router-id>:<n>`, for example `1.1.1.2:2` |
| **RT** | Route Target | Tag saying which VNI imports the route | `<AS>:<VNI>` = **`1:10`** |

`advertise-all-vni` on the leaves tells FRR: "for every VXLAN device the kernel has, create an EVPN instance, send type 3, and send type 2 for each locally learned MAC".
zebra discovers `vxlan10` (VNI 10, `local 1.1.1.X`) and its bridge on its own, so nothing about the VNI needs to be typed in FRR.

### 4.7 IS-IS

**IS-IS** (Intermediate System to Intermediate System) is another **link-state IGP**, like OSPF. It also uses Dijkstra, but it runs directly
on L2 (not over IP), uses levels (L1/L2) instead of areas, and is popular with ISPs and large data centers. The subject requires an IS-IS
engine **service** in the router image. `isisd=yes` starts it. We don't configure it in P3 because the subject requires OSPF there.

| | OSPF | IS-IS |
| :-- | :-- | :-- |
| Runs over | IP (protocol 89) | Directly on L2 (CLNS) |
| Hierarchy | Areas (area 0 = backbone) | Levels (L1, L2) |
| Typical users | Enterprises | ISPs, big DCs |

---

## 5. Part 1: Docker images and GNS3

### 5.1 Goal (from the subject)

- Image 1 (**host**): any system, with at least busybox.
- Image 2 (**router**): packet routing software (zebra/quagga), **BGPD**, **OSPFD**, an **IS-IS** engine, and busybox.
- **No IP address configured by default.**
- Both machines run in GNS3, connected, reachable through GNS3 consoles, with your login in their names.
- Export the GNS3 project as a ZIP with the base images (`P1.gns3project`).

### 5.2 Host image: [P1/_mchegri-1_host](P1/_mchegri-1_host)

```dockerfile
FROM alpine:3
RUN apk update && apk add --no-cache busybox iproute2 net-tools iputils
```

- `FROM alpine:3`: smallest reasonable base.
- `apk add --no-cache`: install without keeping the package index (smaller image).
- No `CMD` line: Alpine's default is `/bin/sh`, so in GNS3 the console gives you a shell directly.

### 5.3 Router image: [P1/_mchegri-2](P1/_mchegri-2)

```dockerfile
FROM quay.io/frrouting/frr:9.1.3          # official FRR image (Alpine-based); has busybox, iproute2, brctl
RUN apk add --no-cache tcpdump             # capture traffic from inside the router
RUN sed -i -e 's/^bgpd=no/bgpd=yes/' \     # enable BGP daemon
           -e 's/^ospfd=no/ospfd=yes/' \   # enable OSPF daemon
           -e 's/^isisd=no/isisd=yes/' /etc/frr/daemons \   # enable IS-IS daemon
 && touch /etc/frr/vtysh.conf              # avoid "vtysh.conf not found" warning
```

- `sed -i 's/^bgpd=no/bgpd=yes/'` edits `/etc/frr/daemons` in place: `^` anchors at line start, `s/old/new/` substitutes.
- **zebra** needs no flag. FRR always starts it.
- The inherited **entrypoint** (`/sbin/tini -- /usr/lib/frr/docker-start`) runs `watchfrr`, which starts and supervises all enabled daemons.
  `tini` is a tiny init (PID 1) that reaps zombie processes and forwards signals.
- No IP address anywhere, as the subject requires.
- Pinned version `9.1.3`: reproducible builds. A floating `latest` tag could break the project later.

### 5.4 Build script: [P1/build.sh](P1/build.sh)

```sh
docker build -t host_mchegri    -f _mchegri-1_host .
docker build -t routeur_mchegri -f _mchegri-2 .
```

These **two tags** (`host_mchegri`, `routeur_mchegri`) are the images used for P1, P2 and P3.
`set -e` stops the script on the first error. `cd "$(dirname "$0")"` lets you run it from any directory.

### 5.5 Verify

```sh
$ docker images | grep mchegri                 # both images exist
# in the router console (GNS3):
$ vtysh -c "show daemons"                      # -> mgmtd zebra bgpd ospfd isisd staticd ... (watchfrr)
$ ps                                           # see /usr/lib/frr/bgpd, ospfd, isisd processes
$ ip addr                                      # no IP configured on eth* (only lo 127.0.0.1)
```

Topology: `host_mchegri-1 (eth0) ──── (eth0) routeur_mchegri-1`. The only requirement is that both run and are reachable by console.

---

## 6. Part 2: VXLAN (static and multicast)

### 6.1 Topology and addressing

```
  host_mchegri-1                                                      host_mchegri-2
  eth1 30.1.1.1/24                                                    eth1 30.1.1.2/24
        │                                                                    │
      eth1                                                                 eth1
  ┌─────┴───────────────┐        ┌──────────────────┐        ┌───────────────┴─────┐
  │ routeur_mchegri-1   │ eth0   │  Switch_mchegri  │  eth0  │ routeur_mchegri-2   │
  │ br0 = eth1+vxlan10  ├────────┤   (GNS3 switch)  ├────────┤ br0 = eth1+vxlan10  │
  │ eth0 10.1.1.1/24    │        └──────────────────┘        │ eth0 10.1.1.2/24    │
  └─────────────────────┘                                    └─────────────────────┘
          ◄═════════════ VXLAN VNI 10 (UDP 4789) over 10.1.1.0/24 ═════════════►
```

- **Underlay**: `10.1.1.0/24` between the routers' `eth0` (through the switch).
- **Overlay**: hosts in `30.1.1.0/24` think they are on the same cable.
- Routers have **no IP on `br0` or `eth1`**. They act as L2 switches toward the hosts.

### 6.2 Static mode: [P2/_mchegri-1_s](P2/_mchegri-1_s) explained line by line

```sh
ip addr add 10.1.1.1/24 dev eth0      # underlay IP
ip link set dev eth0 up               # interfaces are DOWN by default: bring it up

ip link add name vxlan10 type vxlan \
    id 10 \                           # VNI = 10 (subject)
    dev eth0 \                        # send tunnel traffic out of eth0
    remote 10.1.1.2 \                 # STATIC: the one and only peer VTEP
    local 10.1.1.1 \                  # our source IP for outer packets
    dstport 4789                      # IANA port (Linux default would be 8472)
ip link set dev vxlan10 up

ip link add name br0 type bridge      # software switch
ip link set dev br0 up
ip link set dev eth1 up
ip link set dev eth1 master br0       # plug host-facing port into the bridge
ip link set dev vxlan10 master br0    # plug the tunnel into the bridge
```

Router 2 ([P2/_mchegri-2_s](P2/_mchegri-2_s)) is the mirror: `10.1.1.2`, `remote 10.1.1.1`, `local 10.1.1.2`.

Hosts ([P2/_mchegri-1_host](P2/_mchegri-1_host)):

```sh
ip addr add 30.1.1.1/24 dev eth1
ip link set dev eth1 up
```

**Limit of static mode:** each VTEP must list every other VTEP by hand. With N VTEPs that becomes N×(N−1) entries. It doesn't scale.

### 6.3 Multicast mode: [P2/_mchegri-1_g](P2/_mchegri-1_g)

Only the VXLAN line changes:

```sh
ip link add name vxlan10 type vxlan id 10 dev eth0 group 239.1.1.1 dstport 4789
```

- `group 239.1.1.1`: instead of a fixed peer, the VTEP **joins multicast group 239.1.1.1** (it sends an IGMP join on `eth0`).
- BUM traffic (ARP broadcasts, unknown destinations) is sent **to the group**, so every VTEP in the group gets it.
- `dev eth0` is **mandatory** with `group`: the kernel must know which interface joins the group.
- New VTEPs only need to join the same group. No other config changes.
- Still **flood-and-learn**: MACs are learned from received data packets.

### 6.4 What happens during `ping 30.1.1.2` (multicast mode)

1. Host 1 has no ARP entry for `30.1.1.2`, so it **broadcasts an ARP request** out of `eth1`.
2. Router 1's `br0` receives it on `eth1`, **learns** host 1's MAC on port `eth1`, and floods it to all other ports, which means `vxlan10`.
3. `vxlan10` doesn't know the destination (broadcast), so it encapsulates it: outer IP `10.1.1.1 -> 239.1.1.1`, UDP 4789, VNI 10.
4. The switch delivers the multicast to router 2. Router 2's `vxlan10` decapsulates and **learns**: "host 1's MAC is behind VTEP `10.1.1.1`".
   It hands the frame to `br0`, which sends it out of `eth1` to host 2.
5. Host 2 sends a **unicast** ARP reply. Router 2 already knows where host 1 is, so it encapsulates with outer IP `10.1.1.2 -> 10.1.1.1` (**unicast**).
6. Router 1 learns host 2's MAC is behind `10.1.1.2`. From now on the ICMP echo request/reply are **unicast VXLAN** both ways.

In static mode the same thing happens, except step 3 sends to `10.1.1.2` instead of `239.1.1.1`.

### 6.5 What to show in Wireshark (capture on a switch link)

- `vxlan` filter: outer `10.1.1.1 <-> 10.1.1.2` (or `-> 239.1.1.1` for the first ARP in `_g` mode), **VNI: 10**, UDP dst **4789**.
- Inner packets: ARP and ICMP between `30.1.1.1` and `30.1.1.2`.
- `igmp` filter (`_g` mode): membership reports for `239.1.1.1`.

### 6.6 Verify

```sh
# on a router
$ ip -d link show vxlan10            # "vxlan id 10 remote 10.1.1.2 local 10.1.1.1 dev eth0 ... dstport 4789"
                                     #   or "vxlan id 10 group 239.1.1.1 dev eth0 ... dstport 4789"
$ brctl show br0                     # br0 has interfaces eth1 and vxlan10
$ brctl showmacs br0                 # MAC table: local host MAC (port 1) + remote host MAC (port 2 = vxlan10)
$ bridge fdb show dev vxlan10        # "00:00:00:00:00:00 dst 10.1.1.2"  (static default flood target)
                                     # "00:00:00:00:00:00 dst 239.1.1.1 via eth0" (multicast)
                                     # + "<host2 MAC> dst 10.1.1.2" once learned
$ ip maddr show dev eth0             # (_g) shows inet 239.1.1.1: we joined the group
# on host 1
$ ping -c 3 30.1.1.2                 # 0% packet loss
```

---

## 7. Part 3: BGP EVPN with a route reflector

### 7.1 Topology and addressing

```
                              ┌─────────────────────────────┐
                              │ _mchegri-1  SPINE / RR      │
                              │ lo 1.1.1.1/32   AS 1        │
                              │ eth0 .1  eth1 .5  eth2 .9   │
                              └──┬──────────┬──────────┬────┘
                    10.1.1.0/30  │  10.1.1.4/30        │  10.1.1.8/30
                     eth0 .2     │   eth1 .6           │   eth2 .10
          ┌────────────────────┐ │ ┌────────────────────┐ ┌────────────────────┐
          │ _mchegri-2 LEAF 1  ├─┘ │ _mchegri-3 LEAF 2  │ │ _mchegri-4 LEAF 3  │
          │ lo 1.1.1.2/32      │   │ lo 1.1.1.3/32      │ │ lo 1.1.1.4/32      │
          │ br0 = eth1+vxlan10 │   │ br0 = eth0+vxlan10 │ │ br0 = eth0+vxlan10 │
          └─────────┬──────────┘   └─────────┬──────────┘ └─────────┬──────────┘
                  eth1                      eth0                   eth0
          host_mchegri-1             host_mchegri-2          host_mchegri-3
          eth1 20.1.1.1/24           eth0 20.1.1.2/24        eth0 20.1.1.3/24
```

Watch the **interface names**: they differ per leaf (to match the subject's diagram). On leaf 2 and leaf 3, `eth0` goes to the **host**,
and `eth1`/`eth2` go to the spine. Many bugs come from mixing these up when cabling GNS3.

Three layers running at once:

| Layer | Protocol | Who participates | Result |
| :-- | :-- | :-- | :-- |
| Underlay | **OSPF area 0** | all 4 routers | every router can reach `1.1.1.1`-`1.1.1.4` |
| Control plane | **iBGP AS 1, l2vpn evpn**, spine = RR | 3 leaves <-> spine | leaves learn VTEPs (type 3) and MACs (type 2) |
| Data plane | **VXLAN VNI 10** | 3 leaves | host frames tunneled between leaf loopbacks |

### 7.2 Spine / RR: [P3/_mchegri-1](P3/_mchegri-1)

```sh
ip addr add 1.1.1.1/32 dev lo            # router identity
ip addr add 10.1.1.1/30 dev eth0  ...    # one /30 per leaf link (eth0, eth1, eth2), all brought up
```

```
router ospf
 ospf router-id 1.1.1.1
 network 1.1.1.1/32 area 0        # advertise our loopback
 network 10.1.1.0/30 area 0       # run OSPF on eth0 (link to leaf 1)
 network 10.1.1.4/30 area 0       # ... eth1 (leaf 2)
 network 10.1.1.8/30 area 0       # ... eth2 (leaf 3)
!
router bgp 1                      # our AS = 1
 bgp router-id 1.1.1.1
 neighbor ibgp peer-group         # a template of neighbor settings named "ibgp"
 neighbor ibgp remote-as 1        #   peers are in AS 1 -> iBGP
 neighbor ibgp update-source lo   #   source the TCP session from 1.1.1.1
 bgp listen range 1.1.1.0/29 peer-group ibgp   # DYNAMIC neighbors: accept any 1.1.1.0-7
 !
 address-family l2vpn evpn
  neighbor ibgp activate                  # exchange EVPN routes
  neighbor ibgp route-reflector-client    # reflect routes between leaves
 exit-address-family
!
end
write memory                      # save running config to /etc/frr/frr.conf
```

The script feeds these lines to `vtysh` with a **heredoc** (`vtysh << 'EOF' ... EOF`). The quoted `'EOF'` stops the shell from interpreting `$` or `!` inside.

The spine has **no** VXLAN, no bridge and no `advertise-all-vni`. It is a pure IP router plus BGP "mirror".

### 7.3 Leaf / VTEP: [P3/_mchegri-2](P3/_mchegri-2) (leaves 3 and 4 are the same pattern)

```sh
ip addr add 1.1.1.2/32 dev lo
ip addr add 10.1.1.2/30 dev eth0                 # uplink to spine

ip link add dev vxlan10 type vxlan id 10 dstport 4789 local 1.1.1.2 nolearning
#   local 1.1.1.2 : tunnel source = loopback (reachable via OSPF)
#   no remote/group: peers come from BGP EVPN type-3 routes
#   nolearning   : do NOT learn MACs from received data packets -> BGP is the only source
ip link add dev br0 type bridge
ip link set dev eth1 master br0                  # host port
ip link set dev vxlan10 master br0               # tunnel port
ip link set dev br0 up ; ip link set dev vxlan10 up ; ip link set dev eth1 up
```

```
router ospf
 ospf router-id 1.1.1.2
 network 1.1.1.2/32 area 0        # advertise loopback (so others can reach our VTEP + BGP source)
 network 10.1.1.0/30 area 0       # OSPF on uplink
!
router bgp 1
 bgp router-id 1.1.1.2
 neighbor 1.1.1.1 remote-as 1     # one session only: to the RR
 neighbor 1.1.1.1 update-source lo
 !
 address-family l2vpn evpn
  neighbor 1.1.1.1 activate
  advertise-all-vni               # export every local VNI (vxlan10) into EVPN
 exit-address-family
```

| Leaf | Script | Loopback | Uplink (to spine) | Host port | Host |
| :-- | :-- | :-- | :-- | :-- | :-- |
| Leaf 1 | `_mchegri-2` | `1.1.1.2` | `eth0` `10.1.1.2/30` | `eth1` | `host_mchegri-1` `20.1.1.1` (on its `eth1`) |
| Leaf 2 | `_mchegri-3` | `1.1.1.3` | `eth1` `10.1.1.6/30` | `eth0` | `host_mchegri-2` `20.1.1.2` (on its `eth0`) |
| Leaf 3 | `_mchegri-4` | `1.1.1.4` | `eth2` `10.1.1.10/30` | `eth0` | `host_mchegri-3` `20.1.1.3` (on its `eth0`) |

### 7.4 What you should see (same order as the subject)

1. **Routers configured, no hosts yet.**
   - OSPF neighbors reach **Full**. `show ip route` on `_mchegri-4` shows `O>*` routes to `1.1.1.1`, `1.1.1.2`, `1.1.1.3` and the `/30`s.
   - BGP sessions **Established**. On the RR, `show bgp l2vpn evpn summary` lists 3 dynamic neighbors (marked `*`).
   - `show bgp l2vpn evpn` on any leaf: **only type-3 routes** `[3]:[0]:[32]:[1.1.1.X]`, one per leaf. **No type 2**, which is expected.
   - `bridge fdb show dev vxlan10` on a leaf: `00:00:00:00:00:00 dst 1.1.1.3` and `dst 1.1.1.4` (the BUM flood list, built from type 3).
2. **Host 1 starts** (even before it gets an IP): leaf 1 learns its MAC on `eth1` -> zebra notices -> bgpd sends **type 2** `[2]:[0]:[48]:[<host1 MAC>]`
   -> the RR reflects it -> leaves 2 and 3 install `<host1 MAC> dst 1.1.1.2` in their `vxlan10` FDB (marked `extern_learn`).
3. **Host 3 starts**: a second type-2 route appears (next hop `1.1.1.4`).
4. **Ping** `20.1.1.2` / `20.1.1.3` from host 1: works. Wireshark shows VXLAN VNI 10 with ICMP inside, plus OSPF hellos on the links.

### 7.5 Packet walk: host 1 pings host 2

```
host1 ──ARP bcast──► leaf1 br0 ──► vxlan10 ──┬─ copy to 1.1.1.3 (leaf2) ─┐     (head-end replication:
                                             └─ copy to 1.1.1.4 (leaf3) ─┤      one unicast per type-3 peer)
                                                       via spine (plain IP routing, OSPF routes)
leaf2 decap ──► br0 ──► eth0 ──► host2  ──ARP reply (unicast)──► leaf2:
     FDB says host1 MAC -> 1.1.1.2 (from type-2) ──► VXLAN unicast 1.1.1.3 -> 1.1.1.2 ──► leaf1 ──► host1
ICMP echo/reply then flow as unicast VXLAN between 1.1.1.2 and 1.1.1.3.
```

Key points:
- The **outer** packet `1.1.1.2 -> 1.1.1.3` is routed by the spine using OSPF routes. The spine never decapsulates.
- Because of `nolearning`, the leaves trust **only** BGP for remote MACs. If BGP is down, remote unicast fails even though the tunnel exists.

### 7.6 Verify

```sh
# underlay
$ vtysh -c "show ip ospf neighbor"           # spine: 3 neighbors Full; leaf: 1 neighbor Full
$ vtysh -c "show ip route"                   # O>* 1.1.1.X/32 via 10.1.1.Y
$ ping -c 2 -I 1.1.1.2 1.1.1.4               # loopback-to-loopback reachability (from leaf 1)
# control plane
$ vtysh -c "show bgp l2vpn evpn summary"     # neighbors + "PfxRcd" count, state Established
$ vtysh -c "show bgp l2vpn evpn"             # type [3] routes, then [2] routes once hosts are up
$ vtysh -c "show bgp l2vpn evpn route type multicast"   # only type 3
$ vtysh -c "show bgp l2vpn evpn route type macip"       # only type 2
$ vtysh -c "show evpn vni"                   # VNI 10, VxLAN IF vxlan10, # remote VTEPs = 2
$ vtysh -c "show evpn vni 10"                # details incl. remote VTEP list
$ vtysh -c "show evpn mac vni 10"            # MACs: local (leaf port) / remote (VTEP IP)
# data plane (kernel)
$ ip -d link show vxlan10                    # vxlan id 10 local 1.1.1.2 ... nolearning ... dstport 4789
$ bridge fdb show dev vxlan10                # 00:00:00:00:00:00 dst 1.1.1.X (flood) + MAC dst 1.1.1.X extern_learn
$ brctl showmacs br0
# hosts
$ ping -c 3 20.1.1.2 ; ping -c 3 20.1.1.3    # from host_mchegri-1
```

---

## 8. Running it in GNS3

### 8.1 Install (inside the VM)

1. Install Docker (`docker.io` or Docker CE) and add your user to the `docker` group (`sudo usermod -aG docker $USER`, then log out and back in).
2. Install GNS3 (GUI + server). On Ubuntu: the `ppa:gns3/ppa` packages `gns3-gui` and `gns3-server`. Accept `ubridge` permissions and Wireshark capture permissions.
3. Clone this repo and build the images:
   ```sh
   sh P1/build.sh
   docker images | grep mchegri
   ```

### 8.2 Create the templates

GNS3 -> **Edit -> Preferences -> Docker -> Docker containers -> New**:

| Template | Image | Adapters | Console | Notes |
| :-- | :-- | :-- | :-- | :-- |
| `host_mchegri` | `host_mchegri:latest` | 1-2 | telnet | P2 hosts use `eth1`, so give them 2 adapters |
| `routeur_mchegri` | `routeur_mchegri:latest` | **4** | telnet | Spine needs `eth0-eth2` |

Optional: under *Advanced -> Additional directories to make persistent*, add `/etc/frr` to keep FRR config across restarts.

### 8.3 Build each topology

1. **File -> New blank project** (`P1`, `P2`, `P3`).
2. Drag devices and **rename them with the login** (`host_mchegri-1`, `routeur_mchegri-1`, `_mchegri-2`, `Switch_mchegri`...). The subject checks names.
3. Draw links using **exactly** the interfaces in §6.1 / §7.1.
4. Start all nodes (▶).

### 8.4 Apply a config script

Choose one:
- **Paste**: open the node console (double-click), paste the script content. The `vtysh << 'EOF'` block also works when pasted.
- **docker cp** from the VM terminal:
  ```sh
  docker ps --format '{{.Names}}'                     # GNS3 names containers like GNS3.<node>.<uuid>
  docker cp P3/_mchegri-2 <container>:/tmp/conf.sh
  docker exec <container> sh /tmp/conf.sh
  ```

Order for P3: routers first, wait ~30-45 s for OSPF and BGP, show type-3-only state, **then** configure hosts (this matches the subject's demo order).

### 8.5 Capture

Right-click a link -> **Start capture** -> Wireshark opens. Useful filters: `vxlan`, `udp.port == 4789`, `ospf`, `bgp`, `icmp`, `arp`, `igmp`.

### 8.6 Export (deliverable)

**File -> Export portable project** -> tick **"Include base images"** -> save as `P1/P1.gns3project`, `P2/P2.gns3project`, `P3/P3.gns3project`.
Check: `file P3/P3.gns3project` must say *Zip archive data*.

---

## 9. Commands

### 9.1 Docker

| Command | Purpose |
| :-- | :-- |
| `docker build -t NAME -f FILE .` | Build an image |
| `docker images` | List images |
| `docker ps [-a]` | List running (all) containers |
| `docker run -dit --privileged --network none --name N IMG` | Start a detached container with no network |
| `docker exec -it N sh` | Shell inside a container |
| `docker exec N vtysh -c "show ip route"` | Run one command inside |
| `docker cp FILE N:/path` | Copy a file into a container |
| `docker inspect -f '{{.State.Pid}}' N` | PID of the container (used to find its netns) |
| `docker rm -f N` | Force-remove a container |

### 9.2 iproute2 (`ip`) and bridge tools

| Command | Purpose |
| :-- | :-- |
| `ip addr` / `ip a` | Show addresses |
| `ip addr add 10.1.1.1/24 dev eth0` | Add an IP |
| `ip link set dev eth0 up` | Bring an interface up |
| `ip link` / `ip -d link show vxlan10` | Show interfaces / details (`-d`) |
| `ip link add name br0 type bridge` | Create a bridge |
| `ip link set dev eth1 master br0` | Attach a port to a bridge |
| `ip link add vxlan10 type vxlan id 10 dev eth0 remote X local Y dstport 4789` | VXLAN, static |
| `ip link add vxlan10 type vxlan id 10 dev eth0 group 239.1.1.1 dstport 4789` | VXLAN, multicast |
| `ip link add vxlan10 type vxlan id 10 local 1.1.1.2 dstport 4789 nolearning` | VXLAN, EVPN-controlled |
| `ip link del vxlan10` | Delete an interface |
| `ip route` | Kernel routing table |
| `ip neigh` | ARP table |
| `ip maddr show dev eth0` | Joined multicast groups |
| `bridge fdb show [dev vxlan10]` | MAC table including VXLAN destinations |
| `bridge link` | Bridge ports and their state |
| `brctl show` / `brctl showmacs br0` | bridge-utils: bridges / learned MACs |

### 9.3 FRR `vtysh`

| Command | Purpose |
| :-- | :-- |
| `vtysh` | Enter the FRR shell |
| `configure terminal` / `end` / `exit` | Enter / leave config modes |
| `write memory` | Save to `/etc/frr/frr.conf` |
| `show running-config` | Current full configuration |
| `show daemons` | Running FRR daemons |
| `show interface brief` | Interfaces as seen by zebra |
| `show ip route` | RIB (`O` = OSPF, `C` = connected, `>` = selected, `*` = installed in kernel) |
| `show ip ospf neighbor` | OSPF neighbors and states |
| `show ip ospf interface` | OSPF per interface (area, timers, network type) |
| `show ip ospf database` | Link-state database (LSAs) |
| `show bgp summary` | BGP sessions (all address families) |
| `show bgp l2vpn evpn summary` | EVPN sessions |
| `show bgp l2vpn evpn` | All EVPN routes (type 2 / type 3) |
| `show bgp l2vpn evpn route type macip` / `multicast` | Filter by type |
| `show bgp neighbors 1.1.1.1` | Session details (state, timers, capabilities) |
| `show evpn vni [10]` | VNIs known to zebra, remote VTEPs |
| `show evpn mac vni 10` | MAC table per VNI (local / remote) |
| `clear bgp *` | Reset all BGP sessions (debugging) |

### 9.4 Capture and test

| Command | Purpose |
| :-- | :-- |
| `ping -c 3 20.1.1.2` | 3 echo requests |
| `ping -I 1.1.1.2 1.1.1.4` | Ping from a specific source (loopback test) |
| `tcpdump -ni eth0` | Capture everything on eth0, no DNS lookup |
| `tcpdump -ni eth0 udp port 4789` | VXLAN only |
| `tcpdump -ni eth0 proto ospf` | OSPF only |
| `tcpdump -ni eth0 tcp port 179` | BGP only |
| Wireshark filters | `vxlan`, `ospf`, `bgp`, `bgp.type == 2` (UPDATE), `icmp`, `arp`, `igmp` |

---

## 10. Troubleshooting

| Symptom | Likely cause | Check / fix |
| :-- | :-- | :-- |
| `RTNETLINK answers: File exists` | Script run twice (IP or interface already there) | Harmless if config is the same. Otherwise restart the node, or `ip link del vxlan10` / `ip addr flush dev eth0` |
| `Cannot find device "eth2"` | Not enough adapters in the GNS3 template | Set the router template to 4 adapters |
| P2: ping fails | Wrong cabling (host on `eth0` instead of `eth1`), interface down, port not in bridge | `brctl show br0`, `ip link` (look for `UP`), `ip -d link show vxlan10` |
| P2 `_g`: ping fails, `_s` works | Multicast not delivered by the switch, or `dev eth0` missing | `ip maddr show dev eth0` shows `239.1.1.1`; capture to see packets to 239.1.1.1 |
| P3: OSPF neighbor stuck / missing | Link IPs not in the same `/30`, `network` statement doesn't match the IP, interface down, cables swapped | `show ip ospf interface`, `show ip ospf neighbor`, compare §7.1 |
| P3: BGP stuck in `Active` / `Connect` | Loopbacks not reachable (OSPF not converged), `update-source lo` missing, address outside `1.1.1.0/29` | `show ip route` has `1.1.1.1/32`; `ping -I 1.1.1.2 1.1.1.1` |
| BGP Established but 0 EVPN routes | `activate` missing in `address-family l2vpn evpn`, or `advertise-all-vni` missing on leaf | `show running-config`, `show evpn vni` |
| `show evpn vni` empty on a leaf | `vxlan10` created after bgpd with a wrong `local`, or not in a bridge, or down | `ip -d link show vxlan10`, `brctl show`; re-run the script or `clear bgp *` |
| Type 3 ok, no type 2 | Host not started / interface down / host on the wrong leaf port | Bring the host up; `brctl showmacs br0` on the leaf must show its MAC |
| Underlay ping ok, overlay ping fails | Spine not forwarding, or FDB lacks remote entries | On the spine: `sysctl net.ipv4.ip_forward` must be `1`, `vtysh -c "show ip forwarding"`; on leaves: `bridge fdb show dev vxlan10` |
| Config lost after GNS3 restart | Containers are recreated from the image | Re-run scripts, or make `/etc/frr` persistent (§8.2) |

General method: **check from the bottom up**. Physical link up -> IP addresses -> OSPF neighbors -> loopback ping -> BGP session -> EVPN routes -> kernel FDB -> host ping.

---

## 11. Defense

### 11.1 Demo order

1. Show the repo layout (`find -maxdepth 2`) and the ZIP exports (`file P*/P*.gns3project`).
2. **P1**: show both Dockerfiles, explain each line; in GNS3 open both consoles; `vtysh -c "show daemons"`; `ip addr` shows no IP.
3. **P2 static**: `ip -d link show vxlan10`, ping, Wireshark capture showing VNI 10 and inner ICMP.
4. **P2 multicast**: same with `group 239.1.1.1`; `brctl showmacs br0` on both routers.
5. **P3**: `show ip route` on `_mchegri-4` (3 loopbacks via OSPF) -> RR `show bgp l2vpn evpn summary` -> `show bgp l2vpn evpn` (type 3 only) -> start host 1 -> type 2 appears on leaf 1 and leaf 3 -> start host 3 -> second type 2 -> ping all -> Wireshark: VXLAN + ICMP + OSPF.

### 11.2 Questions

**General / Docker / GNS3**
- *What is GNS3?* A network simulator. It wires virtual devices (here Docker containers) and gives consoles and captures.
- *Why Docker and not VMs?* Containers are lightweight, share the kernel and its networking features (bridge, VXLAN), and start in seconds.
- *What is busybox?* One binary providing the standard Unix utilities.
- *Why no IP in the image?* Images are generic building blocks. Each device gets its role from its config script.

**FRR**
- *What does zebra do?* It's the routing manager: it collects routes from bgpd/ospfd, selects the best, and programs the Linux kernel. It also feeds kernel MAC/VNI info to bgpd for EVPN.
- *Quagga vs FRR?* FRR is the actively maintained fork of Quagga.
- *What is vtysh?* A single CLI that talks to all FRR daemons.

**VXLAN**
- *What is VXLAN?* An L2-over-L3 tunnel: an Ethernet frame encapsulated in UDP/IP (port 4789) with a 24-bit VNI.
- *VLAN vs VXLAN?* 12-bit vs 24-bit ID (4K vs 16M). A VLAN lives in one L2 domain; VXLAN stretches L2 over any routed IP network.
- *What is a VTEP?* The endpoint that encapsulates and decapsulates (our routers / leaves).
- *What is a bridge, and why `br0`?* A software switch that links the host port and the VXLAN tunnel into one L2 domain.
- *Static vs multicast?* Static: hard-coded peer, doesn't scale. Multicast: VTEPs join a group, BUM goes to the group, peers discovered automatically. Both are flood-and-learn.
- *What is BUM?* Broadcast, Unknown unicast, Multicast: traffic that must be replicated.
- *VXLAN overhead?* 50 bytes (outer Eth 14 + IP 20 + UDP 8 + VXLAN 8).

**OSPF**
- *Why OSPF here?* Underlay: gives every router reachability to all loopbacks, which BGP sessions and VXLAN tunnels need. The subject requires it.
- *Link-state vs distance-vector?* Link-state routers share the full topology map and compute paths with Dijkstra. Distance-vector routers only share their distances with neighbors.
- *What is area 0?* The backbone area. All areas must connect to it.
- *Where do OSPF hellos go?* Multicast `224.0.0.5`, IP protocol 89.

**BGP / EVPN**
- *What is BGP? An AS?* The Internet's path-vector routing protocol, over TCP 179. An AS is a network under one administration (here AS 1).
- *iBGP vs eBGP?* Same AS vs different AS.
- *What is MP-BGP?* BGP extended with address families, so it can carry IPv6, VPNs and EVPN.
- *Why a route reflector?* iBGP doesn't re-advertise iBGP-learned routes, so without an RR you need a full mesh. The RR reflects routes to its clients, so each leaf needs one session.
- *Is the RR a VTEP?* No. It's control plane only. Data traffic crosses it as plain IP.
- *What does "dynamic relationships" mean in our config?* `bgp listen range 1.1.1.0/29`: the RR accepts any leaf in that range without per-leaf config.
- *What is EVPN?* A BGP address family that advertises MAC/IP reachability and VNI membership. It is a control plane for VXLAN.
- *Type 2 vs type 3?* Type 3: "I'm a VTEP in VNI 10, send me BUM" (sent at startup). Type 2: "this MAC is behind me" (sent when a host becomes active).
- *Why no type 2 at first?* No host has sent a frame yet, so no MAC has been learned.
- *What does `nolearning` do?* It stops the kernel from learning MACs from VXLAN data packets. BGP EVPN is the only source.
- *What does `advertise-all-vni` do?* It exports all local VNIs into EVPN (type 3 + type 2 for local MACs).
- *Why `update-source lo`?* So sessions use the stable loopback address that OSPF advertises.
- *What are RD and RT?* RD makes routes unique; RT decides which VNI imports them (auto `1:10` here).
- *How is BUM handled in P3?* Ingress (head-end) replication: one unicast copy per remote VTEP learned via type 3. No multicast needed.
- *Why "without MPLS"?* EVPN was designed for MPLS. Here VXLAN is the data plane instead (RFC 8365).

**IS-IS**
- *What is IS-IS?* Another link-state IGP (like OSPF). It runs directly on L2, uses levels L1/L2, and is popular with ISPs. It is enabled in our image but not configured in the topologies.

---

## 12. Glossary

| Term | Definition |
| :-- | :-- |
| **AFI/SAFI** | Address Family / Subsequent AF identifiers in MP-BGP (EVPN = 25/70) |
| **ARP** | Address Resolution Protocol: maps an IP address to a MAC on a LAN |
| **AS** | Autonomous System: a network under one routing policy, identified by an ASN |
| **Bridge** | Software L2 switch (`br0`) |
| **BUM** | Broadcast, Unknown unicast, Multicast traffic |
| **CIDR** | `/n` notation for subnet masks |
| **Clos / spine-leaf** | Two-tier DC topology. Every leaf connects to every spine, giving equal-cost paths |
| **Control plane** | Logic that decides where traffic goes (OSPF, BGP) |
| **Data plane** | Actual forwarding of packets (Linux kernel) |
| **ECMP** | Equal-Cost Multi-Path: using several equal routes at once |
| **EVPN** | Ethernet VPN: BGP family carrying MAC/IP and VNI info (RFC 7432 / 8365) |
| **FDB** | Forwarding DataBase: a bridge's MAC table |
| **FRR** | FRRouting, the open-source routing suite |
| **Head-end replication** | The ingress VTEP sends a unicast copy of BUM to each remote VTEP |
| **iBGP / eBGP** | BGP inside one AS / between ASes |
| **IGMP** | Protocol hosts use to join multicast groups |
| **IGP** | Interior Gateway Protocol (OSPF, IS-IS) |
| **IMET** | Inclusive Multicast Ethernet Tag: EVPN route type 3 |
| **IS-IS** | Link-state IGP running over L2 |
| **Loopback** | Virtual always-up interface (`lo`) used as router identity |
| **LSA** | Link-State Advertisement (OSPF) |
| **MAC** | 48-bit L2 hardware address |
| **MP-BGP** | Multiprotocol BGP (RFC 4760) |
| **MTU** | Maximum Transmission Unit (1500 bytes on Ethernet by default) |
| **Namespace (netns)** | Isolated Linux network stack (one per container) |
| **NLRI** | Network Layer Reachability Information: the "route" content BGP carries |
| **OSPF** | Open Shortest Path First, a link-state IGP |
| **Overlay / underlay** | Virtual network on top / physical IP network below |
| **Peer-group** | Reusable BGP neighbor template |
| **RD / RT** | Route Distinguisher / Route Target |
| **RR** | Route Reflector |
| **Router ID** | 32-bit identifier of a router in OSPF/BGP (we use the loopback) |
| **SVI** | Switch Virtual Interface: an IP on a bridge/VLAN (not used here) |
| **veth** | Virtual Ethernet pair (virtual cable) |
| **VNI** | VXLAN Network Identifier (24-bit). Ours is 10 |
| **VTEP** | VXLAN Tunnel End Point |
| **VXLAN** | Virtual eXtensible LAN: L2 over UDP (RFC 7348) |
| **vtysh** | FRR's integrated CLI |
| **watchfrr** | FRR supervisor daemon |
| **zebra** | FRR core daemon: RIB manager and kernel interface |

---

## 13. Submission checklist

Subject requirements vs current repository state:

| Requirement | Status |
| :-- | :-- |
| `P1/`, `P2/`, `P3/` at repo root | done |
| P1 host image with busybox | done, [P1/_mchegri-1_host](P1/_mchegri-1_host) |
| P1 router image: zebra, bgpd, ospfd, isisd, busybox; no default IP | done, [P1/_mchegri-2](P1/_mchegri-2) |
| Commented config files for every device | done |
| P2 VXLAN id 10, `vxlan10`, `br0`, static + group files | done |
| P3 OSPF underlay, iBGP RR, dynamic leaves, EVPN VNI 10 | done |
| Device names include login | done, `mchegri` (check GNS3 node names too) |
| `P1/P1.gns3project`, `P2/P2.gns3project`, `P3/P3.gns3project` (ZIP with base images) | **missing**: `P1/P1.gns3project` is deleted in the working tree, and P2/P3 have none. Export them from GNS3 (§8.6) before submitting |

---

## 14. Resources

**Standards (RFCs)** - free at <https://www.rfc-editor.org/>
- RFC 7348 - VXLAN
- RFC 7432 - BGP MPLS-Based Ethernet VPN (EVPN)
- RFC 8365 - A Network Virtualization Overlay Solution Using EVPN (EVPN over VXLAN)
- RFC 4271 - BGP-4
- RFC 4760 - Multiprotocol Extensions for BGP-4
- RFC 4456 - BGP Route Reflection
- RFC 2328 - OSPF Version 2
- RFC 7938 - Use of BGP for Routing in Large-Scale Data Centers (context: why some DCs use BGP as the underlay)

**Documentation**
- FRRouting user guide: <https://docs.frrouting.org/> (sections *BGP -> EVPN*, *OSPFv2*, *Zebra*, *VTY shell*)
- FRR Docker image: <https://quay.io/repository/frrouting/frr>
- GNS3 docs: <https://docs.gns3.com/> (*Docker support*, *Export portable project*)
- Linux man pages: `man ip-link` (section *VXLAN Type Support*), `man bridge`, `man nsenter`
- Alpine packages: <https://pkgs.alpinelinux.org/>

**Tutorials and articles**
- Vincent Bernat, *VXLAN & Linux*: <https://vincent.bernat.ch/en/blog/2017-vxlan-linux> (all Linux VXLAN modes, including the ones in P2)
- Vincent Bernat, *VXLAN: BGP EVPN with FRR*: <https://vincent.bernat.ch/en/blog/2017-vxlan-bgp-evpn> (very close to P3)
- NVIDIA Cumulus Linux docs, *EVPN* section: <https://docs.nvidia.com/networking-ethernet-software/cumulus-linux/> (clear EVPN route-type explanations; Cumulus uses FRR)
- Wireshark display filter reference: <https://www.wireshark.org/docs/dfref/>

**Books (if you want to go deeper)**
- Dinesh G. Dutt, *BGP in the Data Center* (O'Reilly, free report) and *EVPN in the Data Center*
- Russ White & Ethan Banks, *Computer Networking Problems and Solutions*
