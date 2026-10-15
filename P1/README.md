# P1 - GNS3 with Docker

This part defines and builds the two base Docker images required by the subject:

1. **Host image** (`_mchegri-1_host`):
   - Minimal Alpine Linux 3 base.
   - Includes `busybox`, `iproute2` (`ip`), `net-tools` (`ifconfig`, `arp`), and `iputils` (`ping`).
   - No default IP address configured.

2. **Router image** (`_mchegri-2`):
   - Based on FRRouting (`quay.io/frrouting/frr:9.1.3`, Alpine based).
   - Core routing daemon: `zebra` enabled.
   - Required protocol daemons enabled in `/etc/frr/daemons`:
     - `bgpd=yes` (Border Gateway Protocol, used in P3)
     - `ospfd=yes` (OSPF routing engine, used in P3)
     - `isisd=yes` (IS-IS routing engine)
   - Extra debugging tool: `tcpdump` installed for packet analysis.
   - Supervised by `watchfrr` under `tini` entrypoint.
   - No default IP address configured.

## Build

```sh
sh build.sh
```

This builds and tags the two local images:
- `host_mchegri:latest`
- `routeur_mchegri:latest`

## GNS3 Template Configuration

In GNS3: **Edit > Preferences > Docker > Docker containers > New**:
- **Host**: Name: `host_mchegri`, Image: `host_mchegri:latest`, Console: `telnet`, Adapters: `2` (allows both `eth0` and `eth1`).
- **Router**: Name: `routeur_mchegri`, Image: `routeur_mchegri:latest`, Console: `telnet`, Adapters: `4` (allows `eth0` through `eth3`).

## Verification in GNS3

Connect `host_mchegri-1` to `routeur_mchegri` (e.g. `eth0` <-> `eth0`).

1. **Verify router daemons**:
   ```sh
   vtysh -c 'show daemons'
   # Expected output: mgmtd zebra ospfd bgpd isisd watchfrr staticd
   ```

2. **Verify no default IP addresses**:
   ```sh
   ip addr
   # Expected: only 127.0.0.1 on lo; ethernet interfaces have no configured IP
   ```

3. **Verify host utilities**:
   ```sh
   which busybox ip ifconfig ping
   ```

## Portable Project Export

Subject requirement:
> Export: **File > Export portable project**, check **Include base images**, save as `P1/P1.gns3project`.

