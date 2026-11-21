#!/bin/sh
# Builds the personal Workfloor's web image on a fleet node and imports it into that node's k3s (no registry), from
# the fiuhq/workfloor-ui fork's main. The Font Awesome token is piped from the operator's secrets file into a build
# secret on the node and removed after; it is never printed, logged or put in a layer.
#   usage: fiu/workfloor/image/build.sh [ref] [ssh alias]   (defaults: origin/main, zenbook)
set -eu
here=$(cd "$(dirname "$0")" && pwd)
ref=${1:-origin/main}
alias=${2:-zenbook}
src=$HOME/workspace/projects/fiuhq/workfloor-ui/main
git -C "$src" fetch -q origin
commit=$(git -C "$src" rev-parse "$ref")
# The tag names every build input: the source commit, this Dockerfile and its ignore list.
recipe=$(cat "$here/Dockerfile" "$here/Dockerfile.dockerignore" | shasum -a 256 | cut -c1-8)
tag="workfloor-web:${commit%"${commit#????????????}"}-$recipe"
ctx=/tmp/workfloor-web-ctx
ssh "$alias" "rm -rf $ctx && mkdir -p $ctx"
git -C "$src" archive --format=tar "$commit" | ssh "$alias" "tar -x -C $ctx"
scp -q "$here/Dockerfile" "$alias:$ctx/Dockerfile.fiu"
scp -q "$here/Dockerfile.dockerignore" "$alias:$ctx/Dockerfile.fiu.dockerignore"
python3 -c 'import json,os; print(json.load(open(os.path.expanduser("~/workspace/secrets.json")))["fontawesome"]["pro_npm_token"], end="")' \
  | ssh "$alias" "umask 077; cat > $ctx.fa"
ssh "$alias" "set -e; trap 'rm -f $ctx.fa' EXIT; cd $ctx && DOCKER_BUILDKIT=1 docker build --progress=plain -f Dockerfile.fiu --secret id=fontawesome,src=$ctx.fa -t $tag . && docker save $tag | sudo -n k3s ctr -n k8s.io images import - >/dev/null && echo $tag"
# The image deploy.sh runs: this build's, imported on that node only (the Deployment is pinned to zenbook).
mkdir -p "$here/../generated"
printf 'apiVersion: apps/v1\nkind: Deployment\nmetadata:\n  name: web\nspec:\n  template:\n    spec:\n      containers:\n        - name: web\n          image: %s\n' "$tag" > "$here/../generated/web-image.yaml"
