"""COP-14 story 03 - planning through the OUTSIDE MCP door, as a signed-in person (test admin usr2-q,
account 13, business 49). No AI is involved: tools are called directly over the real door, the way
Claude on the Max plan would call them. Never prints a token. Makes one "(safe to delete)" plan.
Usage: python cop14_plan_door_probe.py -
"""
import json, sys, time, urllib.request, urllib.error
sys.stdout.reconfigure(encoding="utf-8", errors="replace")
from cop5_lib import *
T = token(sys.argv)
DOOR = H + "/x2/mcp/ju0Zh1JM/mcp/stream"
ARCH = 49
PLAN_TOOLS = ["plan_create", "plan_accept_map", "plan_add_job", "plan_add_person", "plan_start_day",
              "plan_schedule_step", "plan_schedule_card", "plan_unschedule_step", "plan_set_start_time", "plan_set_time_window"]

def rpc(method, params, tok):
    body = {"jsonrpc": "2.0", "id": 1, "method": method, "params": params}
    r = urllib.request.Request(DOOR, data=json.dumps(body).encode(), method="POST")
    r.add_header("Content-Type", "application/json"); r.add_header("Accept", "application/json, text/event-stream")
    if tok: r.add_header("Authorization", "Bearer " + tok)
    try: raw = urllib.request.urlopen(r, timeout=120).read().decode(errors="replace")
    except urllib.error.HTTPError as e: return {"_http": e.code, "_body": e.read().decode(errors="replace")[:300]}
    for l in raw.splitlines():
        if l.startswith("data:"): return json.loads(l[5:])
    return {"_raw": raw[:300]}

def call(name, args, tok=T):
    d = rpc("tools/call", {"name": name, "arguments": args}, tok)
    if "error" in d: return {"_err": d["error"].get("message", "")[:300]}
    try:
        res = d["result"]; t = res["content"][0]["text"]
        if res.get("isError"): return {"_err": t[:300]}
        try: return json.loads(t)
        except Exception: return {"_err": t[:300]}
    except Exception: return {"_err": str(d)[:300]}

# 1. the door lists the planner tools, and no publish-to-live tool
d = rpc("tools/list", {}, T)
names = [t["name"] for t in d.get("result", {}).get("tools", [])]
check("signed in: the door lists all 10 planner tools", all(n in names for n in PLAN_TOOLS), sorted(set(PLAN_TOOLS) - set(names)))
check("no tool on the door publishes a plan to live", not any(("publish" in n and n not in ("publish_map", "check_publish_ready")) for n in names), [n for n in names if "publish" in n])
print("  tools on the door:", len(names))

# 2. no sign-in = nothing listed
d0 = rpc("tools/list", {}, None)
check("no sign-in: no tools are listed", not d0.get("result", {}).get("tools"), str(d0)[:160])

# 3. no business named = refused with what to do
r = call("plan_create", {"name": "COP-14 probe should not exist"})
check("no business named: refused, and told to pass journey_architecture_id (E-COP-045)", "_err" in r and "E-COP-045" in r["_err"] and "journey_architecture_id" in r["_err"], r)

# 4. a business outside the caller's account = refused
r = call("plan_create", {"name": "COP-14 probe should not exist 2", "journey_architecture_id": 1})
check("a business outside the account: refused", "_err" in r, r)

# 5. a real draft plan in the caller's own business, as the person
name = f"COP-14 door probe {int(time.time())} (safe to delete)"
r = call("plan_create", {"name": name, "journey_architecture_id": ARCH})
ws = r.get("workspace_id") if isinstance(r, dict) else None
check("plan_create works for the signed-in person in their own business", bool(ws), r)
if ws:
    p = call("plan_add_person", {"workspace_id": ws, "name": "Door probe person", "journey_architecture_id": ARCH})
    agent = p.get("agent_id") if isinstance(p, dict) else None
    check("plan_add_person works through the door", bool(agent), p)
    if agent:
        day = call("plan_start_day", {"workspace_id": ws, "agent_id": agent, "planned_date": time.strftime("%Y-%m-%d"), "journey_architecture_id": ARCH})
        check("plan_start_day makes a DRAFT day", isinstance(day, dict) and day.get("timeline_id") and str(day.get("status", "draft")) == "draft", day)
    # 6. the same plan from a business it is not in = refused (the plan belongs to business 49)
    other = call("plan_add_person", {"workspace_id": ws, "name": "Should be refused", "journey_architecture_id": 48})
    # Known, not fixed: an EMPTY plan (no map yet) is tied to no business, so its creator may name another of
    # their own businesses (copilot/plan_in_business, the shared rule; the in-app copilot behaves the same).
    print("  KNOWN GAP (not a check): empty plan + another own business ->", "refused" if "_err" in other else "allowed")
print("  plan:", ws)
done()
