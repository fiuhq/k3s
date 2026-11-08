#!/bin/sh
# Applies fiu/cluster: the tunnel token Secret from the operator's secrets file (key k3s.tunnel.token, written there by
# the infrastructure that declares the tunnel), then the kustomization twice, because the first pass registers the
# upgrade controller's CRD before its Plans can be created.
#   usage: fiu/cluster/apply.sh   (KUBECONFIG must point at the cluster)
set -eu
here=$(cd "$(dirname "$0")" && pwd)
secrets=$HOME/workspace/secrets.json
token=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["k3s"]["tunnel"]["token"])' "$secrets")
kubectl create namespace cloudflared --dry-run=client -o yaml | kubectl apply -f -
printf %s "$token" | kubectl -n cloudflared create secret generic cloudflared-token --from-file=token=/dev/stdin --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -k "$here" || kubectl wait --for condition=established --timeout=60s crd/plans.upgrade.cattle.io
kubectl apply -k "$here"
