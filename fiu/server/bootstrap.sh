#!/bin/sh
# Installs the fiu k3s server on this node (zenbook's WSL guest). Idempotent: re-running rewrites the config and
# re-runs the vendor installer, which upgrades or restarts in place.
set -eu
here=$(cd "$(dirname "$0")/.." && pwd)
ip=$(ip -4 -o addr show | awk '{print $4}' | cut -d/ -f1 | grep -E '^100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.' | head -n 1)
iface=$(ip -4 -o addr show | awk -v ip="$ip" '$4 ~ "^"ip"/" {print $2}' | head -n 1)
[ -n "$ip" ] || { echo "no tailnet address on this node" >&2; exit 1; }
name=${FIU_NODE_NAME:-$(hostname | tr '[:upper:]' '[:lower:]')}
sudo mkdir -p /etc/rancher/k3s
sudo tee /etc/rancher/k3s/config.yaml >/dev/null <<YAML
# fiuhq/k3s fiu/server/bootstrap.sh: the always-on control plane.
node-name: $name
cluster-init: true
node-ip: $ip
advertise-address: $ip
flannel-iface: $iface
tls-san:
  - $ip
disable:
  - traefik
YAML
if grep -qi microsoft /proc/sys/kernel/osrelease && [ "${iface#eth}" != "$iface" ]; then
  sudo install -m 755 "$here/wsl-mirrored/fiu-pod-masq" /usr/local/sbin/fiu-pod-masq
  sudo install -m 644 "$here/wsl-mirrored/fiu-wsl-offload.service" "$here/wsl-mirrored/fiu-pod-masq.service" /etc/systemd/system/
  command -v ethtool >/dev/null || sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq ethtool
  sudo systemctl daemon-reload
  sudo systemctl enable --now fiu-wsl-offload.service
fi
curl -sfL https://get.k3s.io | INSTALL_K3S_CHANNEL=stable sh -
if [ -f /etc/systemd/system/fiu-pod-masq.service ]; then sudo systemctl enable --now fiu-pod-masq.service; fi
sudo k3s kubectl get nodes -o wide
