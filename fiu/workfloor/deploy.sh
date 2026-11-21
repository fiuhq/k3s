#!/bin/sh
# Applies the personal Workfloor from the Mac. Writes generated/ (gitignored) from the operator's secrets file: the R2
# key for fiu-workfloor-pg (workfloor.r2.pg), its endpoint, and the hatchet login's password, made once and kept there
# so a restored database still accepts it; and the web server's settings (workfloor.web: its session secret, credential
# key and the test account's password, made once and kept there so sessions and sealed values survive a redeploy; the
# R2 files bucket; the backends the header lists, the Mac's Paseo daemon among them, with its password). The web image
# is the one image/build.sh last built and imported (generated/web-image.yaml); run it first.
#   usage: fiu/workfloor/deploy.sh   (KUBECONFIG must point at the cluster)
set -eu
here=$(cd "$(dirname "$0")" && pwd)
secrets=$HOME/workspace/secrets.json
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
web = wf.setdefault("web", {})
changed = False
for key in ("session_secret", "credential_key"):
    if key not in web:
        web[key] = rnd.token_hex(32); changed = True
if "test_password" not in web:
    web["test_password"] = rnd.token_urlsafe(24); changed = True
if "test_email" not in web:
    raise SystemExit("set workfloor.web.test_email in the secrets file: the email the operator signs in as")
import base64, hashlib, hmac
b64 = lambda b: base64.urlsafe_b64encode(b).decode().rstrip("=")
def hash_matches(stored, password):
    try:
        _, n, r, p, salt, key = stored.split("$")
        salt = base64.urlsafe_b64decode(salt + "=" * (-len(salt) % 4))
        got = hashlib.scrypt(password.encode(), salt=salt, n=int(n), r=int(r), p=int(p), dklen=32, maxmem=2**26)
        return hmac.compare_digest(b64(got), key)
    except ValueError:
        return False
if not hash_matches(web.get("test_password_hash", ""), web["test_password"]):
    salt = rnd.token_bytes(16)
    key = hashlib.scrypt(web["test_password"].encode(), salt=salt, n=2**15, r=8, p=1, dklen=32, maxmem=2**26)
    web["test_password_hash"] = f"scrypt${2**15}$8$1${b64(salt)}${b64(key)}"; changed = True
if changed:
    write(path, json.dumps(s, indent=2) + "\n")
origin = "https://wfloor.fiu.one"
email = web["test_email"]
backends = [
    {"name": "fiu", "url": origin, "colour": "pink"},
    {"name": "flxbl", "url": "https://flxbl.workfloor.cloud", "colour": "teal"},
    {"kind": "paseo", "name": "Mac", "url": "wss://phieus-macbook-pro.tail09fc2.ts.net:6767/ws", "colour": "graphite", "people": [email]},
]
files = wf["r2"]["files"]
env = {
    "WORKFLOOR_MODE": "live",
    "WORKFLOOR_ORIGIN": origin,
    "WORKFLOOR_TEAM_ORIGIN": origin,
    "WORKFLOOR_SESSION_SECRET": web["session_secret"],
    "WORKFLOOR_CREDENTIAL_KEY": web["credential_key"],
    "WORKFLOOR_TEST_SIGN_IN_EMAILS": email,
    "WORKFLOOR_TEST_SIGN_IN_PASSWORD_HASH": web["test_password_hash"],
    "WORKFLOOR_INSTANCE_ADMINS": email,
    "WORKFLOOR_FILES": "r2",
    "WORKFLOOR_R2_BUCKET": files["bucket"],
    "WORKFLOOR_R2_ENDPOINT": files["endpoint"],
    "WORKFLOOR_R2_ACCESS_KEY_ID": files["access_key_id"],
    "WORKFLOOR_R2_SECRET_ACCESS_KEY": files["secret_access_key"],
    "WORKFLOOR_BACKENDS": json.dumps(backends, separators=(",", ":")),
    "WORKFLOOR_BACKEND_PASSWORDS": json.dumps({"mac": s["paseo"]["daemon_password"]}),
}
write(os.path.join(out, "web.env"), "".join(f"{k}={v}\n" for k, v in env.items()))
r2 = wf["r2"]["pg"]
write(os.path.join(out, "r2.env"), f"ACCESS_KEY_ID={r2['access_key_id']}\nACCESS_SECRET_KEY={r2['secret_access_key']}\n")
write(os.path.join(out, "hatchet-role.env"), f"username=hatchet\npassword={pg['hatchet_password']}\n")
write(os.path.join(out, "object-store-endpoint.yaml"),
      "apiVersion: barmancloud.cnpg.io/v1\nkind: ObjectStore\nmetadata:\n  name: workfloor-r2\nspec:\n  configuration:\n"
      f"    endpointURL: {r2['endpoint']}\n")
PY
[ -f "$here/generated/web-image.yaml" ] || { echo "no web image yet: run fiu/workfloor/image/build.sh first" >&2; exit 1; }
kubectl apply --server-side -k "$here"
