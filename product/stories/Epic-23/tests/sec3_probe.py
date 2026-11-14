"""SEC-3 — prove the AI tool door over real HTTP. Test accounts only.

Usage:  SEC3_TOKENS=<path to json {"q": token, "p": token}>  python sec3_probe.py
  q = a test user who is switched on AND holds the Intelligent Layer  (must get in)
  p = a test user who is switched on but does NOT hold it             (must be refused)
With no SEC3_TOKENS it runs only the no-token and bad-token checks.
Tokens are read from the file, never printed. Reads one map: the founder's test map 226.
Exit code 1 if any check fails.
"""
import json, os, sys, urllib.request, urllib.error

U = "https://xdjc-i7zz-jhm2.n7e.xano.io/x2/mcp/ju0Zh1JM/mcp/stream"
MAP_ID = 226


def rpc(method, params, bearer=None, query_token=None):
    url = U + (f"?token={query_token}" if query_token else "")
    req = urllib.request.Request(url, data=json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params}).encode(), method="POST")
    req.add_header("Content-Type", "application/json")
    req.add_header("Accept", "application/json, text/event-stream")
    if bearer:
        req.add_header("Authorization", "Bearer " + bearer)
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            raw = r.read().decode(errors="replace")
    except urllib.error.HTTPError as e:
        return {"http": e.code}
    for line in raw.splitlines():
        if line.startswith("data:"):
            return json.loads(line[5:])
    return {"raw": raw[:120]}


def tools(d):
    return len(d.get("result", {}).get("tools", [])) if "result" in d else -1


def got_map(d):
    txt = json.dumps(d)
    return '"result"' in txt and "journey_map" in txt and "isError\": true" not in txt and "error" not in d


def check(name, bearer=None, query_token=None, expect_in=False):
    lst = tools(rpc("tools/list", {}, bearer, query_token))
    call = rpc("tools/call", {"name": "get_map", "arguments": {"journey_map_id": MAP_ID}}, bearer, query_token)
    read = got_map(call)
    ok = (lst > 0 and read) if expect_in else (lst <= 0 and not read)
    print(f"{'PASS' if ok else 'FAIL'}  {name:<34} tools={lst:<3} map_read={read}  (expected {'IN' if expect_in else 'REFUSED'})")
    return ok


results = [
    check("no token"),
    check("made-up token (header)", bearer="not.a.token"),
    check("made-up token (address)", query_token="not.a.token"),
]
path = os.environ.get("SEC3_TOKENS")
if path:
    t = json.load(open(path))
    results += [
        check("granted user, header", bearer=t["q"], expect_in=True),
        check("granted user, address", query_token=t["q"], expect_in=True),
        check("user without the module", bearer=t["p"]),
    ]
else:
    print("SKIP  token checks (SEC3_TOKENS not set) — a skip is not a pass")
print(f"{sum(results)}/{len(results)} passed")
sys.exit(0 if all(results) else 1)
