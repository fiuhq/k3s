#!/bin/sh
# Joins a fleet machine to the fiu k3s cluster as an agent, over the tailnet.
#   usage: fiu/agent/bootstrap.sh <server ssh alias> [<node name> <node ssh alias>]
# With no node: the Mac, through an OrbStack Ubuntu VM with its own tailnet identity (the first run prints a
# Tailscale login link; open it, approve, then run this again).
# With a node: a Linux machine already on the tailnet that its ssh alias reaches with passwordless sudo, such as
# g14's fleet VM: fiu/agent/bootstrap.sh zenbook g14 g14-fleet
set -eu
# A node name without its ssh alias would rewrite the Mac's VM under the wrong name.
[ $# -eq 1 ] || [ $# -eq 3 ] || { echo 'usage: bootstrap.sh <server ssh alias> [<node name> <node ssh alias>]' >&2; exit 64; }
server=${1:?usage: bootstrap.sh <server ssh alias> [<node name> <node ssh alias>]}
node=${2:-mac}
alias=${3:-}

if [ -z "$alias" ]; then
  vm=k3s-mac
  on_node() { orb -m "$vm" -u root sh -s; }
  orb list -q 2>/dev/null | grep -qx "$vm" || orb create ubuntu:noble "$vm"
  orb -m "$vm" -u root sh -c 'command -v tailscale >/dev/null || curl -fsSL https://tailscale.com/install.sh | sh'
  if ! orb -m "$vm" -u root tailscale ip -4 >/dev/null 2>&1; then
    orb -m "$vm" -u root tailscale up --hostname="$vm" --accept-dns=false --timeout=20s || true
    echo "approve the login link above, then run this again" >&2
    exit 2
  fi
else
  on_node() { ssh "$alias" sudo -n sh -s; }
fi

token=$(ssh "$server" 'sudo cat /var/lib/rancher/k3s/server/node-token')
server_ip=$(ssh "$server" "awk '/^node-ip:/ {print \$2}' /etc/rancher/k3s/config.yaml")
# The token travels inside the script on stdin, never on a command line.
on_node <<SCRIPT
set -eu
mkdir -p /etc/rancher/k3s
(umask 077 && printf '%s\n' '$token' > /etc/rancher/k3s/join-token)
ip=\$(tailscale ip -4)
cat > /etc/rancher/k3s/config.yaml <<YAML
# fiuhq/k3s fiu/agent/bootstrap.sh: the $node fleet machine as an agent.
node-name: $node
node-ip: \$ip
flannel-iface: tailscale0
node-label:
  - fiu.one/node=$node
YAML
curl -sfL https://get.k3s.io | INSTALL_K3S_CHANNEL=stable K3S_URL="https://$server_ip:6443" K3S_TOKEN_FILE=/etc/rancher/k3s/join-token sh -s - agent
SCRIPT
