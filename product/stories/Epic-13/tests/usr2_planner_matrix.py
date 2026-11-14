"""USR-2 story 04 — Planner and Execution told apart by one group-level gate.

Runs the same matrix against any API group that has `usr_require_planner_group`
attached. Default: the scratch group. Pass the real planner base to run it live:
    python usr2_planner_matrix.py api:PE5iDldw <work_item_id> <work_task_id>
Env: USR2_PW (test fixture password). Test users only.

Expected (P planning only, S execution only, Q intelligence only, R all grants
but switched off). "pass" below means: not refused by the gate (any status
other than 401/403), since on the real group the endpoint may answer 404 for a
test account that owns no such job.
"""
import json, os, sys, urllib.request, urllib.error

HOST = "https://xdjc-i7zz-jhm2.n7e.xano.io"
AUTH = "api:RPonubWS"
GROUP = sys.argv[1] if len(sys.argv) > 1 else "api:G6ltFxPq"
JOB = sys.argv[2] if len(sys.argv) > 2 else "1"
TASK = sys.argv[3] if len(sys.argv) > 3 else "1"
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
for who in ("p", "q", "s"):
    s, b = call("POST", AUTH, "auth/login", {"email": f"usr2-{who}@example.com", "password": PW})
    tok[who] = b.get("authToken") if isinstance(b, dict) else None
# R is switched off, so cannot sign in any more (SEC-2). Its pre-existing token, if any:
try:
    import tempfile
    tok["r"] = json.load(open(os.path.join(tempfile.gettempdir(), "usr2_tokens.json"))).get("r")
except Exception:
    tok["r"] = None

ENDPOINTS = [
    ("GET", "workspace", "planning only"),
    ("GET", "perform/today", "execution only"),
    ("POST", f"work_task/{TASK}/event", "execution only"),
    ("GET", f"work_item/{JOB}", "either"),
]
# who -> set of endpoint kinds they may pass
MAY = {"p": {"planning only", "either"}, "s": {"execution only", "either"}, "q": set(), "r": set()}
NAMES = {"p": "P planner only ", "s": "S execution only", "q": "Q intelligence only", "r": "R switched off  "}

bad = 0
for who in ("p", "s", "q", "r"):
    if not tok.get(who):
        print(f"{NAMES[who]} | no token available — skipped")
        continue
    for method, path, kind in ENDPOINTS:
        body = {} if method == "POST" else None
        s, b = call(method, GROUP, path, body, tok[who])
        refused = s in (401, 403)
        want_pass = kind in MAY[who]
        want_code = "E-USR-005" if who == "r" else "E-USR-006"
        ok = (not refused) if want_pass else (s == 403 and code_of(b) == want_code)
        bad += 0 if ok else 1
        print(f"{'PASS' if ok else 'FAIL'} {NAMES[who]} | {method:4s} {path:24s} ({kind:14s}) -> {s} {code_of(b)}")
print(f"\n{'ALL PASS' if bad == 0 else str(bad) + ' FAILED'} on {GROUP}")
