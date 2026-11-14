"""USR-2 story 03 — the Intelligent Layer group gate, with its three exemptions.

Default target is the scratch group; pass the real one to run it live:
    python usr2_journey_matrix.py api:ER4MRRWZ
Env: USR2_PW (test fixture password). Test users only, GET requests only.

Users: Q intelligence only · P planner only · S execution only · F all three ·
R all three but switched off (uses a token issued before the switch-off).
"pass" means: not refused by the gate (status other than 401/403).
"""
import json, os, sys, tempfile, urllib.request, urllib.error

HOST = "https://xdjc-i7zz-jhm2.n7e.xano.io"
AUTH = "api:RPonubWS"
GROUP = sys.argv[1] if len(sys.argv) > 1 else "api:G6ltFxPq"
PW = os.environ["USR2_PW"]


def call(method, group, path, body=None, token=None):
    req = urllib.request.Request(f"{HOST}/{group}/{path}", data=json.dumps(body).encode() if body is not None else None, method=method)
    req.add_header("Content-Type", "application/json")
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return r.status, json.loads(r.read() or b"null")
    except urllib.error.HTTPError as e:
        raw = e.read()
        try:
            return e.code, json.loads(raw)
        except Exception:
            return e.code, raw[:200].decode(errors="replace")


def code_of(b):
    m = b.get("message", "") if isinstance(b, dict) else str(b)
    for c in ("E-USR-005", "E-USR-006"):
        if c in m:
            return c
    return ""


tok = {}
for who in ("q", "p", "s", "f"):
    s, b = call("POST", AUTH, "auth/login", {"email": f"usr2-{who}@example.com", "password": PW})
    tok[who] = b.get("authToken") if isinstance(b, dict) else None
try:
    tok["r"] = json.load(open(os.path.join(tempfile.gettempdir(), "usr2_tokens.json"))).get("r")
except Exception:
    tok["r"] = None

ENDPOINTS = [("journey_map", "intelligence"), ("account/me", "no module"), ("journey_map_attachable", "intel or planner")]
MAY = {
    "q": {"intelligence", "no module", "intel or planner"},
    "p": {"no module", "intel or planner"},
    "s": {"no module"},
    "f": {"intelligence", "no module", "intel or planner"},
    "r": set(),
}
NAMES = {"q": "Q intelligence only", "p": "P planner only     ", "s": "S execution only   ", "f": "F all modules      ", "r": "R switched off     "}

bad = 0
for who in ("q", "p", "s", "f", "r"):
    if not tok.get(who):
        print(f"{NAMES[who]} | no token available — skipped")
        continue
    for path, kind in ENDPOINTS:
        s, b = call("GET", GROUP, path, token=tok[who])
        refused = s in (401, 403)
        want_pass = kind in MAY[who]
        want_code = "E-USR-005" if who == "r" else "E-USR-006"
        ok = (not refused) if want_pass else (s == 403 and code_of(b) == want_code)
        bad += 0 if ok else 1
        print(f"{'PASS' if ok else 'FAIL'} {NAMES[who]} | GET {path:24s} ({kind:16s}) -> {s} {code_of(b)}")
print(f"\n{'ALL PASS' if bad == 0 else str(bad) + ' FAILED'} on {GROUP}")
