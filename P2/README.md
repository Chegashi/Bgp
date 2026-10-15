# P2 - Discovering VXLAN (Static & Multicast)

In this part, we bridge two remote hosts across an IP network using a **VXLAN** tunnel interface (`vxlan10`) attached to a Linux bridge (`br0`).

## Topology

```text
host_mchegri-1 (eth1/eth0)      routeur_mchegri-1           Switch_mchegri           routeur_mchegri-2      host_mchegri-2 (eth1/eth0)
    30.1.1.1/24           ─────── eth1       eth0 ─────────── e0     e1 ─────────── eth0       eth1 ───────      30.1.1.2/24
                                 10.1.1.1/24                                         10.1.1.2/24
```

- **Underlay IP**: `10.1.1.1/24` (Router 1) and `10.1.1.2/24` (Router 2) over `eth0`.
- **Overlay IP**: `30.1.1.1/24` (Host 1) and `30.1.1.2/24` (Host 2).
- **VXLAN Parameters**: VNI `10`, interface `vxlan10`, standard UDP destination port `4789`.
- **Bridge**: `br0` binds local host port (`eth1`) and tunnel port (`vxlan10`).

## Configuration Modes

1. **Static Unicast (`_s`)**:
   - `_mchegri-1_s` / `_mchegri-2_s`
   - Explicit peer IP specified with `remote 10.1.1.X`.
   - BUM (Broadcast, Unknown unicast, Multicast) frames are unicast directly to the remote VTEP.

2. **Multicast Group (`_g`)**:
   - `_mchegri-1_g` / `_mchegri-2_g`
   - VTEPs join the multicast group `239.1.1.1` via IGMP on `eth0`.
   - BUM frames (e.g. ARP requests) are sent to `239.1.1.1` so all group members receive them.
   - Once a unicast reply is received, the remote MAC is learned in the FDB and subsequent frames are unicast.

3. **Host Scripts**:
   - `_mchegri-1_host` / `_mchegri-2_host`
   - Automatically configure `eth1` (matching the subject diagram) or fall back to `eth0`.

*Note: All router scripts are idempotent and cleanly delete existing `vxlan10` and `br0` before re-creating them, allowing direct switching between static and multicast modes.*

## Testing Procedure

### Step 1: Static Mode
1. Run `_mchegri-1_s` on Router 1.
2. Run `_mchegri-2_s` on Router 2.
3. Run `_mchegri-1_host` on Host 1 and `_mchegri-2_host` on Host 2.
4. From Host 1:
   ```sh
   ping -c 3 30.1.1.2
   ```

### Step 2: Dynamic Multicast Mode
1. Run `_mchegri-1_g` on Router 1.
2. Run `_mchegri-2_g` on Router 2.
3. From Host 1:
   ```sh
   ping -c 3 30.1.1.2
   ```

## Verification Commands

On the routers:
```sh
# Inspect VXLAN interface settings (verify ID 10, port 4789, remote/group)
ip -d link show vxlan10

# Inspect bridge membership (must show eth1 and vxlan10)
brctl show br0

# Check bridge MAC table
brctl showmacs br0

# Check VXLAN Forwarding Database (remote MAC -> remote VTEP IP)
bridge fdb show dev vxlan10
```

## Wireshark Packet Inspection

Start packet capture on the link between `routeur_mchegri-1` and `Switch_mchegri`:
- Filter: `vxlan` or `udp.port == 4789`
- In static mode (`_s`): outer destination IP is `10.1.1.2`.
- In multicast mode (`_g`): initial ARP broadcast has outer destination IP `239.1.1.1`. Subsequent ICMP packets are unicast (`10.1.1.2`).
- Inside the UDP 4789 payload: VXLAN header with `VNI = 10`, encapsulating the inner Ethernet frame (`30.1.1.1 -> 30.1.1.2`).

## Portable Project Export

Subject requirement:
> Export: **File > Export portable project**, check **Include base images**, save as `P2/P2.gns3project`.

