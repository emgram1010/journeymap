"""SEC-2 — the 'after' test: every door closed, nothing else broken. Test accounts only.

Env: SEC2_PW, SEC2_X, SEC2_Y, SEC2_MAGIC_A, SEC2_MAGIC_C (one-time magic tokens).
User B must temporarily hold the platform-admin flag for the last block.
"""
import json, os, urllib.request, urllib.error

HOST = "https://xdjc-i7zz-jhm2.n7e.xano.io"
AUTH, MEM = "api:RPonubWS", "api:Fcgmwc6Y"
PW = os.environ["SEC2_PW"]
X, Y = int(os.environ["SEC2_X"]), int(os.environ["SEC2_Y"])


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


def msg(b):
    return b.get("message") if isinstance(b, dict) else str(b)[:120]


def me(tok):
    s, b = call("GET", AUTH, "auth/me", token=tok)
    return b.get("account_id") if isinstance(b, dict) else None


results = []


def check(name, ok, detail):
    results.append((name, bool(ok), detail))


_, la = call("POST", AUTH, "auth/login", {"email": "sec2-a@example.com", "password": PW})
_, lb = call("POST", AUTH, "auth/login", {"email": "sec2-b@example.com", "password": PW})
ta, tb = la.get("authToken"), lb.get("authToken")
check("active users still sign in", ta and tb, "A and B got tokens")

# --- F-4
s, b = call("POST", AUTH, "auth/login", {"email": "sec2-c@example.com", "password": PW})
check("F-4 switched-off, right password -> E-USR-005, no token", s == 403 and "(E-USR-005)" in str(msg(b)) and "authToken" not in b, f"{s} {msg(b)}")
s, b = call("POST", AUTH, "auth/login", {"email": "sec2-c@example.com", "password": "wrong-Pass1"})
check("F-4 switched-off, wrong password -> generic only", s == 403 and msg(b) == "Invalid Credentials.", f"{s} {msg(b)}")
s, b = call("POST", AUTH, "reset/magic-link-login", {"email": "sec2-c@example.com", "magic_token": os.environ["SEC2_MAGIC_C"]})
check("F-4 switched-off, magic link -> E-USR-005", s == 403 and "(E-USR-005)" in str(msg(b)), f"{s} {msg(b)}")
s, b = call("POST", AUTH, "reset/magic-link-login", {"email": "sec2-a@example.com", "magic_token": os.environ["SEC2_MAGIC_A"]})
check("magic link still works for an active user", s == 200 and b.get("authToken"), f"{s}")

# --- F-2
s, b = call("GET", MEM, f"account/details?account_id={Y}")
check("F-2 no token -> refused", s == 401, f"{s} {msg(b)}")
s, b = call("GET", MEM, f"account/details?account_id={Y}", token=ta)
check("F-2 someone else's account -> not found", s == 404 and "ai_context" not in (b if isinstance(b, dict) else {}), f"{s} {msg(b)}")
s, b = call("GET", MEM, "account/details?account_id=999999", token=ta)
check("F-2 missing account -> the same answer", s == 404 and msg(b) == "Account not found.", f"{s} {msg(b)}")
s, b = call("GET", MEM, f"account/details?account_id={X}", token=ta)
check("F-2 own account by number -> ok", s == 200 and b.get("id") == X, f"{s}")
s, b = call("GET", MEM, "account/details", token=ta)
check("F-2 own account, number omitted -> ok", s == 200 and b.get("id") == X, f"{s}")

# --- F-1
before = me(ta)
s, b = call("POST", MEM, "user/join_account", {"account_id": Y}, ta)
check("F-1 normal user join -> E-OBS-001, account unchanged", s == 403 and "(E-OBS-001)" in str(msg(b)) and me(ta) == before == X, f"{s} {msg(b)} account {before}->{me(ta)}")

# --- F-3
s, b = call("POST", MEM, "account", {"name": "SEC-2 should not exist"}, ta)
check("F-3 normal user create account -> E-OBS-001, stays put", s == 403 and "(E-OBS-001)" in str(msg(b)) and me(ta) == X, f"{s} {msg(b)}")

# --- platform admin (test user B holds the flag for this block)
s, b = call("GET", MEM, f"account/details?account_id={X}", token=tb)
check("platform admin reads any account", s == 200 and b.get("id") == X, f"{s}")
s, b = call("POST", MEM, "account", {"name": "SEC-2 platform-made (safe to delete)"}, tb)
made = b.get("account", {}).get("id") if isinstance(b, dict) else None
check("platform admin creates an account and STAYS in their own", s == 200 and made and me(tb) == Y, f"{s} new={made} B still in {me(tb)}")
s, b = call("POST", MEM, "user/join_account", {"account_id": X}, tb)
leaked = [k for k in (b if isinstance(b, dict) else {}) if k in ("password", "password_reset", "email")]
check("platform admin join works, response is shaped", s == 200 and b.get("account_id") == X and not leaked, f"{s} keys={sorted(b) if isinstance(b, dict) else b}")
s, b = call("POST", MEM, "user/join_account", {"account_id": Y}, tb)
check("platform admin moved back", s == 200 and me(tb) == Y, f"{s}")

# --- sign-up is untouched
s, b = call("POST", AUTH, "auth/signup", {"name": "SEC2 Signup", "email": "sec2-signup@example.com", "password": PW})
ts = b.get("authToken") if isinstance(b, dict) else None
s2, m = call("GET", AUTH, "auth/me", token=ts) if ts else (0, {})
check("sign-up still creates an account and its admin", s == 200 and m.get("role") == "admin" and (m.get("account_id") or 0) > 0, f"{s} role={m.get('role')} account={m.get('account_id')}")

bad = [r for r in results if not r[1]]
for name, ok, detail in results:
    print(("PASS " if ok else "FAIL ") + name + "  |  " + str(detail))
print(f"\n{len(results) - len(bad)}/{len(results)} passed" + (f"  new_account={made}" if made else ""))
