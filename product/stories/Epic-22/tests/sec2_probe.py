"""SEC-2 story 01 — prove the open doors over real HTTP, test accounts only."""
import json, os, sys, urllib.request, urllib.error

HOST = "https://xdjc-i7zz-jhm2.n7e.xano.io"
AUTH, MEM, PLAN, JM = "api:RPonubWS", "api:Fcgmwc6Y", "api:PE5iDldw", "api:ER4MRRWZ"
PW = os.environ["SEC2_PW"]
X, Y = int(os.environ["SEC2_X"]), int(os.environ["SEC2_Y"])


def call(method, group, path, body=None, token=None):
    url = f"{HOST}/{group}/{path}"
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
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


def login(email):
    s, b = call("POST", AUTH, "auth/login", {"email": email, "password": PW})
    return s, (b.get("authToken") if isinstance(b, dict) else None), b


def msg(b):
    return b.get("message") if isinstance(b, dict) else str(b)[:120]


out = {}

s, ta, _ = login("sec2-a@example.com")
s2, tb, _ = login("sec2-b@example.com")
out["login A/B"] = [s, s2]

# F-4 switched-off user C, right password
s, tc, b = login("sec2-c@example.com")
out["F-4 switched-off C login"] = {"status": s, "token_issued": bool(tc), "message": None if tc else msg(b)}

# F-2 account details with no token
s, b = call("GET", MEM, f"account/details?account_id={Y}")
out["F-2 details no token"] = {"status": s, "keys": sorted(b.keys()) if isinstance(b, dict) else msg(b), "name": b.get("name") if isinstance(b, dict) else None}

# F-1 A joins Y
s, me0 = call("GET", AUTH, "auth/me", token=ta)
s, b = call("POST", MEM, "user/join_account", {"account_id": Y}, ta)
leaked = sorted(k for k in (b.keys() if isinstance(b, dict) else []) if k in ("password", "password_reset"))
s_me, me1 = call("GET", AUTH, "auth/me", token=ta)
s_tm, tm = call("GET", MEM, "account/my_team_members", token=ta)
out["F-1 A joins Y"] = {
    "status": s,
    "account_before": me0.get("account_id") if isinstance(me0, dict) else None,
    "account_after": me1.get("account_id") if isinstance(me1, dict) else None,
    "A_can_list_Y_team": [m.get("name") for m in tm] if isinstance(tm, list) else msg(tm),
    "response_contains_secret_fields": leaked,
}
# put A back
s, b = call("POST", MEM, "user/join_account", {"account_id": X}, ta)
out["restore A to X"] = s

# F-3 A starts a new account
s, b = call("POST", MEM, "account", {"name": "SEC-2 spinoff (safe to delete)"}, ta)
new_acc = b.get("account", {}).get("id") if isinstance(b, dict) else None
s_me, me2 = call("GET", AUTH, "auth/me", token=ta)
out["F-3 A spins off"] = {"status": s, "new_account": new_acc, "A_account_now": me2.get("account_id") if isinstance(me2, dict) else None, "A_role": me2.get("role") if isinstance(me2, dict) else None}
s, b = call("POST", MEM, "user/join_account", {"account_id": X}, ta)
out["restore A to X (2)"] = s

# F-6 module doors: B has no grants; C is switched off
s, b = call("GET", PLAN, "workspace", token=tb)
out["F-6 planner as B (no grant)"] = {"status": s, "message": msg(b) if s != 200 else "ALLOWED"}
s, b = call("GET", JM, "journey_architecture", token=tb)
out["F-6 intelligence as B (no grant)"] = {"status": s, "message": msg(b) if s != 200 else "ALLOWED"}
if tc:
    s, b = call("GET", PLAN, "workspace", token=tc)
    out["switched-off C on planner"] = {"status": s, "message": msg(b) if s != 200 else "ALLOWED"}
    s, b = call("GET", MEM, "account/my_team_members", token=tc)
    out["switched-off C lists team"] = {"status": s, "count": len(b) if isinstance(b, list) else msg(b)}

print(json.dumps(out, indent=2))
