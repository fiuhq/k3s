#!/bin/sh
# Applies the personal Workfloor from the Mac. Writes generated/ (gitignored) from the operator's secrets file: the R2
# key for fiu-workfloor-pg (workfloor.r2.pg), its endpoint, and the hatchet login's password, made once and kept there
# so a restored database still accepts it.
#   usage: fiu/workfloor/deploy.sh   (KUBECONFIG must point at the cluster; FIU_SECRETS defaults to the workspace's file)
set -eu
here=$(cd "$(dirname "$0")" && pwd)
secrets=${FIU_SECRETS:-$HOME/workspace/secrets.json}
mkdir -p "$here/generated"
python3 - "$secrets" "$here/generated" <<'PY'
import json, os, secrets as rnd, sys, tempfile
path, out = sys.argv[1], sys.argv[2]
def write(dst, text):
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(os.path.realpath(dst)))
    try:
        with os.fdopen(fd, "w") as f:
            f.write(text); f.flush(); os.fsync(f.fileno())
        os.replace(tmp, os.path.realpath(dst))
    except BaseException:
        os.unlink(tmp); raise
s = json.load(open(path))
wf = s["workfloor"]
pg = wf.setdefault("postgres", {})
if "hatchet_password" not in pg:
    pg["hatchet_password"] = rnd.token_urlsafe(24)
    write(path, json.dumps(s, indent=2) + "\n")
r2 = wf["r2"]["pg"]
write(os.path.join(out, "r2.env"), f"ACCESS_KEY_ID={r2['access_key_id']}\nACCESS_SECRET_KEY={r2['secret_access_key']}\n")
write(os.path.join(out, "hatchet-role.env"), f"username=hatchet\npassword={pg['hatchet_password']}\n")
write(os.path.join(out, "object-store-endpoint.yaml"),
      "apiVersion: barmancloud.cnpg.io/v1\nkind: ObjectStore\nmetadata:\n  name: workfloor-r2\nspec:\n  configuration:\n"
      f"    endpointURL: {r2['endpoint']}\n")
PY
kubectl apply --server-side -k "$here"
