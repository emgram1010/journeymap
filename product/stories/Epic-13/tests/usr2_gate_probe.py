"""USR-2 stories 03/04 — does a module middleware really refuse? Scratch groups only.

Env: USR2_PW. Step 'login' prints nothing secret; tokens are kept in a temp file
between the two steps so user R can be switched off in between.
Usage: python usr2_gate_probe.py login   |   python usr2_gate_probe.py call
"""
import json, os, sys, tempfile, urllib.request, urllib.error

HOST = "https://xdjc-i7zz-jhm2.n7e.xano.io"
AUTH = "api:RPonubWS"
GROUP_GATED = "api:G6ltFxPq"      # group-level middleware
GROUP_ENDPOINT = "api:zIY73PPx"   # per-endpoint middleware
TOK = os.path.join(tempfile.gettempdir(), "usr2_tokens.json")


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
    return b.get("message") if isinstance(b, dict) and "message" in b else b


if sys.argv[1] == "login":
    toks = {}
    for who in ("p", "q", "r"):
        s, b = call("POST", AUTH, "auth/login", {"email": f"usr2-{who}@example.com", "password": os.environ["USR2_PW"]})
        toks[who] = b.get("authToken") if isinstance(b, dict) else None
        print(who, s, "token" if toks[who] else msg(b))
    json.dump(toks, open(TOK, "w"))
else:
    toks = json.load(open(TOK))
    rows = [
        ("group-level  | P no grant        ", GROUP_GATED, "ping", toks["p"]),
        ("group-level  | Q granted         ", GROUP_GATED, "ping", toks["q"]),
        ("group-level  | R switched off    ", GROUP_GATED, "ping", toks["r"]),
        ("group-level  | no token          ", GROUP_GATED, "ping", None),
        ("per-endpoint | P no grant        ", GROUP_ENDPOINT, "gated", toks["p"]),
        ("per-endpoint | Q granted         ", GROUP_ENDPOINT, "gated", toks["q"]),
        ("per-endpoint | R switched off    ", GROUP_ENDPOINT, "gated", toks["r"]),
        ("control open | P no grant        ", GROUP_ENDPOINT, "open", toks["p"]),
    ]
    for name, g, path, t in rows:
        s, b = call("GET", g, path, token=t)
        print(name, "->", s, msg(b))
