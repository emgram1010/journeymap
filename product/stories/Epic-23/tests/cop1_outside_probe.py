"""COP-1 — the outside door: owner stamping, list filtering, "is this business yours".

Real HTTP against the gated tool address, as a TEST user (account 13). Creates a few
"(safe to delete)" fixtures in that test account. Never prints the token.

Usage:  COP1_TOKEN_FILE=<file holding the test user's token>  python cop1_outside_probe.py
Optional: COP1_EXPECT=report|enforce (default report) — what the gate should do with a map or
business that belongs to another account.
"""
import json, os, sys, urllib.request

TOK = open(os.environ["COP1_TOKEN_FILE"]).read().strip()
EXPECT = os.environ.get("COP1_EXPECT", "report")
U = "https://xdjc-i7zz-jhm2.n7e.xano.io/x2/mcp/ju0Zh1JM/mcp/stream"
FOREIGN_MAP, FOREIGN_ARCH = 176, 46      # belong to another account
OWN_MAPS = {235, 236}                     # fixtures already in the test account


def call(name, args):
    body = {"jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": {"name": name, "arguments": args}}
    req = urllib.request.Request(U, data=json.dumps(body).encode(), method="POST")
    req.add_header("Content-Type", "application/json")
    req.add_header("Accept", "application/json, text/event-stream")
    req.add_header("Authorization", "Bearer " + TOK)
    try:
        raw = urllib.request.urlopen(req, timeout=180).read().decode(errors="replace")
    except Exception as e:
        return {"_err": str(e)[:160]}
    for line in raw.splitlines():
        if line.startswith("data:"):
            d = json.loads(line[5:])
            if "error" in d:
                return {"_err": str(d["error"].get("message", ""))[:200]}
            t = d["result"]["content"][0]["text"]
            try:
                return json.loads(t)
            except Exception:
                return {"_err": t[:200]}
    return {"_err": raw[:160]}


results = []


def check(name, ok, detail=""):
    results.append(ok)
    print(("PASS  " if ok else "FAIL  ") + name + (f"   [{detail}]" if detail else ""))


def refused(r):
    return isinstance(r, dict) and "_err" in r


# 1 — a workspace belongs to its maker, whatever account_id the caller sends
ws = call("create_workspace", {"title": "COP-1 ws fixture (safe to delete)", "account_id": 2})
check("create_workspace stamps the caller's account (sent account 2, a different one)",
      ws.get("account_id") == 13 and ws.get("owner_user") == 22, f"account={ws.get('account_id')} owner={ws.get('owner_user')} {ws.get('_err', '')}")
ws_id = ws.get("id", 0)

# 2 — a map belongs to its maker
m1 = call("create_journey_map", {"title": "COP-1 map in ws (safe to delete)", "journey_architecture_id": ws_id})
jm1 = m1.get("journey_map", {})
check("create_journey_map (in own workspace) stamps owner and account",
      jm1.get("account_id") == 13 and jm1.get("owner_user") == 22, f"account={jm1.get('account_id')} owner={jm1.get('owner_user')} {m1.get('_err', '')}")
m2 = call("create_journey_map", {"title": "COP-1 loose map (safe to delete)"})
jm2 = m2.get("journey_map", {})
check("create_journey_map (no workspace) stamps owner and account — never 0",
      jm2.get("account_id") == 13 and jm2.get("owner_user") == 22, f"account={jm2.get('account_id')} owner={jm2.get('owner_user')} {m2.get('_err', '')}")
mine = OWN_MAPS | {jm1.get("id"), jm2.get("id")}

# 3 — lists show only the caller's account
lm = call("list_maps", {})
ids = {r["id"] for r in lm.get("results", [])}
check("list_maps shows the caller's maps", mine <= ids, f"{len(ids)} listed {lm.get('_err', '')}")
check("list_maps shows no other account's map", FOREIGN_MAP not in ids and 227 not in ids and bool(ids), f"foreign present: {sorted(ids & {176, 227})}")
la = call("list_maps", {"architecture_id": FOREIGN_ARCH})
check("list_maps filtered to another account's business is empty", la.get("count") == 0, f"count={la.get('count')} {la.get('_err', '')}")

sm = call("search_maps", {"query": ""})
sids = {r["map_id"] for r in sm.get("results", [])} if "results" in sm else None
check("search_maps runs (was 'Invalid pipe.') and shows no other account's map",
      sids is not None and FOREIGN_MAP not in sids and 227 not in sids, f"count={sm.get('count')} {sm.get('_err', '')}")
sq = call("search_maps", {"query": "Party"})
check("search_maps with a query runs", "results" in sq, f"count={sq.get('count')} {sq.get('_err', '')}")

# 4 — scenarios: own business works, someone else's shows nothing (or is refused)
ls = call("list_scenarios", {"journey_architecture_id": ws_id})
check("list_scenarios (own business) lists the new map with its owner",
      any(s["id"] == jm1.get("id") and s.get("owner_name") not in (None, "", "Unknown") for s in ls.get("scenarios", [])),
      f"count={ls.get('count')} {ls.get('_err', '')}")
lf = call("list_scenarios", {"journey_architecture_id": FOREIGN_ARCH})
if EXPECT == "enforce":
    check("list_scenarios (another account's business) is refused", refused(lf), str(lf)[:80])
else:
    check("list_scenarios (another account's business) shows nothing", lf.get("count") == 0, f"count={lf.get('count')} {lf.get('_err', '')}")

# 5 — a clone belongs to its maker
cl = call("clone_scenario", {"journey_architecture_id": ws_id, "source_map_id": jm1.get("id")})
new_id = (cl.get("journey_map") or cl.get("new_map") or cl).get("id") if isinstance(cl, dict) else None
ls2 = call("list_scenarios", {"journey_architecture_id": ws_id})
clone_rows = [s for s in ls2.get("scenarios", []) if s.get("cloned_from_map_id") == jm1.get("id")]
check("clone_scenario makes a copy owned by the caller",
      len(clone_rows) == 1 and clone_rows[0].get("owner_name") not in (None, "", "Unknown"),
      f"clones={len(clone_rows)} owner={clone_rows[0].get('owner_name') if clone_rows else None} {cl.get('_err', '') if isinstance(cl, dict) else ''}")

# 6 — another account's map
gm = call("get_map", {"journey_map_id": FOREIGN_MAP})
if EXPECT == "enforce":
    check("get_map on another account's map is refused", refused(gm), str(gm)[:80])
    gx = call("get_map", {"journey_map_id": 99999999})
    check("...with the same answer as a map that does not exist", refused(gx) and gx.get("_err") == gm.get("_err"), f"{gm.get('_err')} | {gx.get('_err')}")
    uc = call("update_cell", {"journey_map_id": FOREIGN_MAP, "stage_key": "s1", "lens_key": "description", "content": "should never land"})
    check("update_cell on another account's map is refused", refused(uc), str(uc)[:80])
    cj = call("create_journey_map", {"title": "COP-1 must not exist", "journey_architecture_id": FOREIGN_ARCH})
    check("create_journey_map inside another account's business is refused", refused(cj), str(cj)[:80])
    own = call("get_map", {"journey_map_id": 236})
    check("get_map on the caller's own map still works", "journey_map" in own, own.get("_err", ""))
else:
    check("get_map on another account's map still answers (report mode refuses nothing)", "journey_map" in gm, gm.get("_err", ""))

print(f"{sum(results)}/{len(results)} passed  (expecting gate mode: {EXPECT})")
sys.exit(0 if all(results) else 1)
