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
   on a WSL guest in mirrored networking mode, the two fixes in `wsl-mirrored/`.
2. The Mac agent bootstrap lands in a follow-up once proven.
3. `kubectl apply -k cluster/`, twice on a fresh cluster: the first apply installs the system-upgrade-controller CRD
   and the second creates its upgrade Plans once the CRD is established. The system-upgrade-controller keeps every node on the stable channel (k3s's own
   updater); the descheduler moves preferred workloads back to the Mac.

## WSL mirrored networking

A WSL guest in mirrored mode needs two fixes before pods reach the internet:

- `fiu-wsl-offload.service`: TCP segmentation offload on the mirrored interfaces truncates forwarded segments (a
  container's 1.5 kB TLS ClientHello arrives as 771 bytes), so it is turned off on every `eth*` interface.
- `fiu-pod-masq.service`: Windows hands a reply back to the guest only on ports inside the guest's reserved range
  (`net.ipv4.ip_local_port_range`), and flannel masquerades pod traffic with random ports. Two rules first in
  `POSTROUTING` keep pod connections inside that range on whichever interface they leave by. Bound to `k3s.service`, so they are re-applied after
  flannel writes its own on every start.

A host-network listener is needed to receive traffic from other machines: mirrored mode only forwards inbound
connections to ports a Linux socket listens on, and the service load balancer's iptables forwarding never listens.
