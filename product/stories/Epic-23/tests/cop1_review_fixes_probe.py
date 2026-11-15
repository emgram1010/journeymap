"""COP-1 review fixes (2026-11-14) — live checks as TEST admin q (account 13). Never prints the token.
Usage: python cop1_review_fixes_probe.py <magic_token_for_usr2-q>   (token file is deleted at the end)
"""
import json, sys, urllib.request, urllib.error
H = "https://xdjc-i7zz-jhm2.n7e.xano.io"; MEM = H + "/api:Fcgmwc6Y"; MCP = H + "/x2/mcp/ju0Zh1JM/mcp/stream"
COPILOT = 26; RUN = 1; RUN_MAP = 244; OTHER_OWN_MAP = 235

def req(method, url, body=None, tok=None, sse=False):
    r = urllib.request.Request(url, data=json.dumps(body).encode() if body is not None else None, method=method)
    r.add_header("Content-Type", "application/json")
    if sse: r.add_header("Accept", "application/json, text/event-stream")
    if tok: r.add_header("Authorization", "Bearer " + tok)
    try: raw = urllib.request.urlopen(r, timeout=180).read().decode(errors="replace"); code = 200
    except urllib.error.HTTPError as e: raw = e.read().decode(errors="replace"); code = e.code
    if sse:
        for l in raw.splitlines():
            if l.startswith("data:"):
                d = json.loads(l[5:])
                if "error" in d: return code, {"_err": d["error"]["message"]}
                t = d["result"]["content"][0]["text"]
                try: return code, json.loads(t)
                except Exception: return code, {"_err": t[:200]}
        return code, {"_err": raw[:200]}
    try: return code, json.loads(raw)
    except Exception: return code, {"_raw": raw[:200]}

c, b = req("POST", H + "/api:RPonubWS/reset/magic-link-login", {"magic_token": sys.argv[1], "email": "usr2-q@example.com"})
T = b["authToken"]
tool = lambda n, a: req("POST", MCP, {"jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": {"name": n, "arguments": a}}, T, True)[1]
res = []
def check(name, ok, detail=""):
    res.append(ok); print(("PASS  " if ok else "FAIL  ") + name + (f"   [{detail}]" if detail else ""))
err = lambda r: isinstance(r, dict) and ("_err" in r)

r = tool("get_workflow_state", {"journey_map_id": RUN_MAP, "execution_id": RUN})
check("get_workflow_state: own run on its own map still loads", not err(r) and r.get("found") is True, str(r)[:120])
r = tool("get_workflow_state", {"journey_map_id": OTHER_OWN_MAP, "execution_id": RUN})
check("get_workflow_state: run named under a DIFFERENT map is refused", err(r) and "not found" in r["_err"].lower(), str(r)[:120])
r = tool("get_workflow_state", {"journey_map_id": RUN_MAP})
check("get_workflow_state: no execution_id still falls back to the map's run", not err(r), str(r)[:120])
r = tool("save_workflow_state", {"journey_map_id": OTHER_OWN_MAP, "execution_id": RUN, "status": "cancelled"})
check("save_workflow_state: run under a different map is never updated", err(r), str(r)[:120])
r = tool("save_workflow_state", {"journey_map_id": RUN_MAP, "execution_id": RUN, "subject_label": "COP-1 test"})
check("save_workflow_state: own run on its own map still saves", not err(r) and r.get("execution_id") == RUN, str(r)[:120])
r = tool("export_workflow_output", {"execution_id": RUN, "format": "json"})
check("export: no map id -> gated on the run's own map, allowed for its owner", not err(r) and "Run ID" in (r.get("content") or ""), str(r)[:120])
r = tool("export_workflow_output", {"execution_id": RUN, "format": "json", "journey_map_id": OTHER_OWN_MAP})
check("export: mismatched map id refused", err(r), str(r)[:120])
r = tool("export_workflow_output", {"execution_id": 999999, "format": "json"})
check("export: unknown run refused", err(r), str(r)[:120])
r = tool("list_maps", {})
check("list_maps still lists the caller's maps", not err(r) and r.get("count", 0) > 0, f"count={r.get('count')} {r.get('_err','')}")
r = tool("search_maps", {"query": ""})
check("search_maps still runs", not err(r), str(r)[:100])

c, b = req("POST", MEM + "/admin/user_update", {"user_id": COPILOT, "email": "someone@example.com"}, T)
check("admin cannot change the copilot's email (E-COP-012)", c >= 400 and "E-COP-012" in json.dumps(b), f"http {c}")
c, b = req("POST", MEM + "/admin/user_update", {"user_id": COPILOT, "name": "Test Copilot"}, T)
check("admin can still rename the copilot", c == 200 and b.get("name") == "Test Copilot", f"http {c} {str(b)[:80]}")
c, b = req("POST", MEM + "/admin/user_role", {"user_id": COPILOT, "new_role": "admin"}, T)
check("admin cannot change the copilot's role (E-COP-013)", c >= 400 and "E-COP-013" in json.dumps(b), f"http {c}")
c, team = req("GET", MEM + "/account/my_team_members", None, T)
p = [m for m in team if m.get("id") not in (COPILOT, 22)][0]
c, b = req("POST", MEM + "/admin/user_update", {"user_id": p["id"], "name": p["name"]}, T)
check("regression: a person can still be renamed", c == 200, f"http {c}")
c, b = req("POST", MEM + "/admin/user_role", {"user_id": p["id"], "new_role": p.get("role") or "member"}, T)
check("regression: a person's role can still be set", c == 200, f"http {c} {str(b)[:80]}")
print(f"\n{sum(res)}/{len(res)} passed")
