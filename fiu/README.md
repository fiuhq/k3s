# fiu k3s

This fork carries no change to k3s itself. `fiu/` holds how the fiu fleet runs it; upstream merges never touch it.

## Layout

| Node | Role | Why |
|---|---|---|
| zenbook (WSL, Ubuntu) | server: control plane + embedded etcd | it stays on; the cluster keeps scheduling while the Mac sleeps |
| Mac (an OrbStack Ubuntu VM, arm64) | agent, labelled `fiu.one/node=mac` | the preferred node for workloads; it sleeps and travels |

Nodes talk over the tailnet. With two nodes only one can hold etcd, so the always-on node does; a third server can
join later with `--server` because the first started with `cluster-init`.

Workloads that should prefer the Mac use a preferred node affinity on `fiu.one/node=mac` and tolerate an unreachable
node for 30 s, so they move to zenbook when the Mac goes away. The descheduler (`cluster/`) evicts them from zenbook
once the Mac is Ready again, so they move back.

## Bootstrap

1. `server/bootstrap.sh` on zenbook (in WSL). Installs k3s from the stable channel with the node's tailnet address and,
   on a WSL guest in mirrored networking mode, the two fixes in `wsl-mirrored/`. Flannel is pinned to the interface
   that carries the tailnet address (unset, k3s would use the default-route interface), so re-run it if Windows
   renumbers the mirrored adapters.
2. `agent/bootstrap.sh <server ssh alias>` on the Mac. Creates the OrbStack VM, joins it to the tailnet (the first
   run prints a login link; approve it and run again) and joins it to the cluster with the server's token, read over
   ssh. Any other Linux fleet machine already on the tailnet joins the same way by naming it and its ssh alias:
   `agent/bootstrap.sh zenbook g14 g14-fleet` joined g14's fleet VM (2026-11-20). OrbStack must start at login
   (`orb config set app.start_at_login true`), or the Mac's node stays NotReady after every reboot.
3. `cluster/apply.sh`. Creates the tunnel token Secret from the secrets file, then applies `cluster/` (twice: the first
   pass registers the system-upgrade-controller CRD before its Plans). The system-upgrade-controller keeps every node
   on the stable channel (k3s's own updater); the descheduler moves preferred workloads back to the Mac; cloudflared
   carries every public site.

## Networking between the nodes

Flannel uses WireGuard (`wireguard-native`). VXLAN does not work here: the OrbStack VM's kernel carries Ubuntu's fan
patch, and its VXLAN device never sent an encapsulated packet to the server. On a WSL server in mirrored mode the
WireGuard listen port sits inside `net.ipv4.ip_local_port_range` (`/etc/rancher/k3s/flannel.json`), because Windows
drops the peer's handshake replies on any other port; `net.ipv4.ip_local_reserved_ports`
(`/etc/sysctl.d/90-fiu-flannel-wg.conf`) keeps that port from being handed out as an ephemeral one before flannel
binds it. Measured: a pod on the Mac then reaches CoreDNS on the server in about 70 ms.

## Public sites

`cloudflared.yaml` runs one Cloudflare Tunnel connector per node over HTTP/2 (QUIC never connected from either node).
The tunnel, its routes (hostname to in-cluster service), DNS and Access are declared outside this repo; the connector
only needs the token.

## WSL mirrored networking

A WSL guest in mirrored mode needs two fixes before pods reach the internet:

- `fiu-wsl-offload.service`: TCP segmentation offload on the mirrored interfaces truncates forwarded segments (a
  container's 1.5 kB TLS ClientHello arrives as 771 bytes), so it is turned off on every `eth*` interface at boot.
  `fiu-pod-masq` turns it off again on every k3s start, which covers an adapter Windows adds later.
- `fiu-pod-masq.service`: Windows hands a reply back to the guest only on ports inside the guest's reserved range
  (`net.ipv4.ip_local_port_range`), and flannel masquerades pod traffic with random ports. Two rules first in
  `POSTROUTING` keep pod connections inside that range on whichever interface they leave by. Bound to
  `k3s.service`, so they are re-applied after flannel writes its own on every start.

A host-network listener is needed to receive traffic from other machines: mirrored mode only forwards inbound
connections to ports a Linux socket listens on, and the service load balancer's iptables forwarding never listens.

## Over-the-air updates for the fleet's mobile builds

`ota/` runs xprem, an Expo Updates protocol server, with its PostgreSQL, both pinned to the control-plane node (the
database volume is local to it). Phones fetch update manifests and assets from it and check each update's signature
against the certificate built into the app; CI publishes with an app-scoped token. Update bundles live in an R2
bucket, and a nightly CronJob dumps the database to the same bucket under `backups/`. The database holds the update
signing keys, sealed with a master key that `ota/deploy.sh` generates once and keeps in the operator's secrets file:
with it and the latest dump, the server can be rebuilt on another node; without it, every app needs a new build.
The vendor's hourly usage ping is turned off (`DISABLE_TELEMETRY`), so the server's address stays private.

## Paseo agents in pods

`agents/` runs Paseo agents the way flxbl-stack's codev runs its tasks: one stateful pod per agent, from the
agent-sandbox controller (`cluster/agent-sandbox/`). Nothing lives only in the pod: its home is its own volume, code
leaves through `git push` and the pull request, and the logins arrive as a Secret.

- `agents/Dockerfile`: the agent image, the fiuhq/paseo fork's daemon image (`docker/base/Dockerfile`, built from
  fork main) plus Claude Code, Codex, OpenCode and GitHub's CLI. The fork image's web UI bundle needs more Node heap
  than the default on a 5-CPU node: build it with `NODE_OPTIONS=--max-old-space-size=6144`.
- `agents/sandbox-trial.yaml`: one Sandbox pinned to g14 with a 20 Gi home, its daemon reachable only from the
  tailnet at `wss://g14-fleet.tail09fc2.ts.net:8443` (`tailscale serve --bg --https=8443 http://<Service ClusterIP>:6767`
  on the VM). The daemon has no password, like the fleet's other daemons, so its Service never becomes a NodePort. Its Secret `paseo-agent-logins` holds `claude-credentials.json`, `gh-token`, `git-name` and `git-email`.

Measured 2026-11-20: an agent started through the pod's daemon cloned fiuhq/k3s, committed and pushed a branch as the
operator, and the Mac listed it over the tailnet address. Not yet carried: lending the Claude login into the Secret
when it rotates, no-mistakes (its gate is the operator's, on the Mac), a warm pool, and the placement job creating a
SandboxClaim.
