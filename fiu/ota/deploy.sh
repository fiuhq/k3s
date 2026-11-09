#!/bin/sh
# Applies the OTA server from the Mac. Writes generated/public.env and generated/secrets.env (gitignored) from the
# operator's secrets file, generating the server's own secrets once and keeping them there: the database master key
# is the only way to unseal the update signing keys, so it must outlive any node.
#   usage: fiu/ota/deploy.sh   (KUBECONFIG must point at the cluster; FIU_SECRETS defaults to the workspace's file)
set -eu
here=$(cd "$(dirname "$0")" && pwd)
secrets=${FIU_SECRETS:-$HOME/workspace/secrets.json}
mkdir -p "$here/generated"
python3 - "$secrets" "$here/generated" <<'PY'
import base64, json, os, secrets as rnd, sys
path, out = sys.argv[1], sys.argv[2]
s = json.load(open(path))
ota = s["ota"]
srv = ota.setdefault("server", {})
changed = False
def keep(key, make):
    global changed
    if key not in srv:
        srv[key] = make(); changed = True
    return srv[key]
keep("jwt_secret", lambda: base64.b64encode(os.urandom(32)).decode())
keep("db_keys_master_key_b64", lambda: base64.b64encode(os.urandom(32)).decode())
keep("postgres_password", lambda: rnd.token_urlsafe(24))
keep("admin_email", lambda: "fiu@ota.local")
keep("admin_password", lambda: "Fiu-" + rnd.token_urlsafe(18) + "9a!")
if changed:
    fd = os.open(path, os.O_WRONLY | os.O_TRUNC); os.write(fd, (json.dumps(s, indent=2) + "\n").encode()); os.close(fd)
r2 = ota["r2"]
public = {"BASE_URL": ota["public_url"], "S3_BUCKET_NAME": r2["bucket"]}
sec = {
    "JWT_SECRET": srv["jwt_secret"], "DB_KEYS_MASTER_KEY_B64": srv["db_keys_master_key_b64"],
    "POSTGRES_PASSWORD": srv["postgres_password"],
    "DB_URL": f"postgresql://xprem:{srv['postgres_password']}@postgres:5432/xprem?sslmode=disable",
    "ADMIN_EMAIL": srv["admin_email"], "ADMIN_PASSWORD": srv["admin_password"],
    "AWS_ACCESS_KEY_ID": r2["access_key_id"], "AWS_SECRET_ACCESS_KEY": r2["secret_access_key"], "AWS_BASE_ENDPOINT": r2["endpoint"],
}
for name, d in (("public.env", public), ("secrets.env", sec)):
    fd = os.open(os.path.join(out, name), os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    os.write(fd, "".join(f"{a}={b}\n" for a, b in d.items()).encode()); os.close(fd)
PY
kubectl apply -k "$here"
