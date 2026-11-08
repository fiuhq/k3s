#!/bin/sh
# Joins the Mac to the fiu k3s cluster as an agent: an OrbStack Ubuntu VM with its own tailnet identity.
#   usage: fiu/agent/bootstrap.sh <server ssh alias>
# The first run prints a Tailscale login link; open it, approve, then run this again.
set -eu
server=${1:?usage: bootstrap.sh <server ssh alias>}
vm=k3s-mac
orb list -q 2>/dev/null | grep -qx "$vm" || orb create ubuntu:noble "$vm"
orb -m "$vm" -u root sh -c 'command -v tailscale >/dev/null || curl -fsSL https://tailscale.com/install.sh | sh'
if ! orb -m "$vm" -u root tailscale ip -4 >/dev/null 2>&1; then
  orb -m "$vm" -u root tailscale up --hostname="$vm" --accept-dns=false --timeout=20s || true
  echo "approve the login link above, then run this again" >&2
  exit 2
fi
token=$(ssh "$server" 'sudo cat /var/lib/rancher/k3s/server/node-token')
server_ip=$(ssh "$server" "awk '/^node-ip:/ {print \$2}' /etc/rancher/k3s/config.yaml")
printf '%s\n' "$token" | orb -m "$vm" -u root sh -c 'mkdir -p /etc/rancher/k3s && umask 077 && cat > /etc/rancher/k3s/join-token'
orb -m "$vm" -u root env SERVER_IP="$server_ip" sh -c '
  set -eu
  ip=$(tailscale ip -4)
  cat > /etc/rancher/k3s/config.yaml <<YAML
# fiuhq/k3s fiu/agent/bootstrap.sh: the Mac, the preferred node for workloads.
node-name: mac
node-ip: $ip
flannel-iface: tailscale0
node-label:
  - fiu.one/node=mac
YAML
  curl -sfL https://get.k3s.io | INSTALL_K3S_CHANNEL=stable K3S_URL="https://$SERVER_IP:6443" K3S_TOKEN_FILE=/etc/rancher/k3s/join-token sh -s - agent
'
