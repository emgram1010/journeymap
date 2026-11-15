"""COP-5 / COP-7 probes - shared helpers. Signs in as TEST admin usr2-q (account 13) with a one-time
magic token and caches the session token in a temp file OUTSIDE the repo. Never prints a token.
Usage in a probe:  from cop5_lib import *;  T = token(sys.argv)
"""
import json, os, sys, tempfile, urllib.request, urllib.error
H = "https://xdjc-i7zz-jhm2.n7e.xano.io"
AUTH = H + "/api:RPonubWS"; JM = H + "/api:ER4MRRWZ"; PL = H + "/api:PE5iDldw"; MEM = H + "/api:Fcgmwc6Y"
CACHE = os.path.join(tempfile.gettempdir(), "cop5_probe_session.json")
res = []

def req(m, u, b=None, t=None, to=120):
    r = urllib.request.Request(u, data=json.dumps(b).encode() if b is not None else None, method=m)
    r.add_header("Content-Type", "application/json")
    if t: r.add_header("Authorization", "Bearer " + t)
    try:
        raw = urllib.request.urlopen(r, timeout=to).read()
        return 200, (json.loads(raw) if raw else {})
    except urllib.error.HTTPError as e:
        raw = e.read().decode(errors="replace")
        try: return e.code, json.loads(raw)
        except Exception: return e.code, {"message": raw[:300]}

def token(argv):
    """argv[1] = a fresh magic token (first run) or omitted (reuse the cached session)."""
    if len(argv) > 1 and argv[1] != "-":
        c, b = req("POST", AUTH + "/reset/magic-link-login", {"magic_token": argv[1], "email": "usr2-q@example.com"})
        assert c == 200 and b.get("authToken"), "sign-in failed: %s" % str(b)[:200]
        json.dump({"t": b["authToken"]}, open(CACHE, "w"))
    return json.load(open(CACHE))["t"]

def check(n, ok, d=""):
    res.append(bool(ok)); print(("PASS  " if ok else "FAIL  ") + n + (("   [" + str(d)[:300] + "]") if d and not ok else ""))

def done():
    print("\n%d/%d passed" % (sum(res), len(res))); sys.exit(0 if all(res) else 1)

def short(b, n=700):
    return json.dumps(b)[:n]
