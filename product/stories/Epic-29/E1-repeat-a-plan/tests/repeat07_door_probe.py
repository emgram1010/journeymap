"""REPEAT-1 story 07 - the plan_repeat tool through the OUTSIDE MCP door, the way Claude on the Max plan
would call it: once as a signed-in person (test member usr2-q admin, account 13, business 47) and once as an
AI member (user 24, limited to plan <PLAN>, 2 writes an hour). Every call is a real tools/call.
Never prints a token. Makes "(safe to delete)" plans only; the caller deletes them afterwards.
Usage: python repeat07_door_probe.py <fresh magic token for usr2-q> <AI member token> <source plan> <other plan>
"""
import json, sys, urllib.request, urllib.error

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
H = "https://xdjc-i7zz-jhm2.n7e.xano.io"
AUTH = H + "/api:RPonubWS"
PL = H + "/api:PE5iDldw:v1"
DOOR = H + "/x2/mcp/ju0Zh1JM/mcp/stream"
ARCH = 47
magic, AI_TOKEN, PLAN, OTHER = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
res = []
import time, datetime
_N = int(time.time() // 60) % 3000
def D(i):  # a fresh Monday far from the source plan, different every run so no run finds an old copy
    return (datetime.date(2028, 1, 3) + datetime.timedelta(days=7 * (_N * 7 + i))).isoformat()


def http(method, url, body=None, tok=None):
    r = urllib.request.Request(url, data=json.dumps(body).encode() if body is not None else None, method=method)
    r.add_header("Content-Type", "application/json")
    if tok:
        r.add_header("Authorization", "Bearer " + tok)
    try:
        raw = urllib.request.urlopen(r, timeout=180).read()
        return 200, (json.loads(raw) if raw else {})
    except urllib.error.HTTPError as e:
        raw = e.read().decode(errors="replace")
        try:
            return e.code, json.loads(raw)
        except Exception:
            return e.code, {"message": raw[:300]}


def rpc(method, params, tok):
    body = {"jsonrpc": "2.0", "id": 1, "method": method, "params": params}
    r = urllib.request.Request(DOOR, data=json.dumps(body).encode(), method="POST")
    r.add_header("Content-Type", "application/json")
    r.add_header("Accept", "application/json, text/event-stream")
    if tok:
        r.add_header("Authorization", "Bearer " + tok)
    try:
        raw = urllib.request.urlopen(r, timeout=180).read().decode(errors="replace")
    except urllib.error.HTTPError as e:
        return {"_http": e.code, "_body": e.read().decode(errors="replace")[:300]}
    for l in raw.splitlines():
        if l.startswith("data:"):
            return json.loads(l[5:])
    return {"_raw": raw[:300]}


def call(name, args, tok):
    d = rpc("tools/call", {"name": name, "arguments": args}, tok)
    if "error" in d:
        return {"_err": d["error"].get("message", "")[:400]}
    try:
        r = d["result"]
        t = r["content"][0]["text"]
        if r.get("isError"):
            return {"_err": t[:400]}
        try:
            return json.loads(t)
        except Exception:
            return {"_err": t[:400]}
    except Exception:
        return {"_err": str(d)[:400]}


def check(n, ok, d=""):
    res.append(bool(ok))
    print(("PASS  " if ok else "FAIL  ") + n + (("   [" + str(d)[:300] + "]") if d and not ok else ""))


st, d = http("POST", AUTH + "/reset/magic-link-login", {"magic_token": magic, "email": "usr2-q@example.com"})
assert st == 200 and d.get("authToken"), "sign-in failed"
P = d["authToken"]


def history(ws):
    return http("GET", f"{PL}/workspace/{ws}/repeat-history", None, P)[1]


def board(ws):
    return http("GET", f"{PL}/workspace/{ws}/board", None, P)[1]


# ---- the door lists the tool; nothing on it publishes
names = [t["name"] for t in rpc("tools/list", {}, P).get("result", {}).get("tools", [])]
check("T-07-6 the door lists plan_repeat", "plan_repeat" in names, names[-6:])
check("no tool on the door publishes a plan to live", not any(("publish" in n and n not in ("publish_map", "check_publish_ready")) for n in names))

print("\n== as a person ==")
before = history(PLAN)
r = call("plan_repeat", {"workspace_id": PLAN, "journey_architecture_id": ARCH, "periods": 3}, P)
check("T-07-1 preview (create left out) answers 'preview' and makes no plan", r.get("mode") == "preview" and r.get("workspace_id") == 0 and len(r.get("periods", [])) == 3, r)
check("T-07-1 the preview wrote nothing", history(PLAN)["repeated_to"] == before["repeated_to"])
check("the preview leads with what would be left out, in plain words", r.get("message", "").startswith("Left out (") and "Old" in r.get("message", ""), r.get("message"))
check("the preview says it is only a preview", "Preview only" in r.get("message", ""))
prev_counts = r.get("counts")

r = call("plan_repeat", {"workspace_id": PLAN, "journey_architecture_id": ARCH, "create": True}, P)
check("creating without a start date is refused and says what to do", "_err" in r and "start date" in r["_err"].lower(), r)
r = call("plan_repeat", {"workspace_id": PLAN, "journey_architecture_id": ARCH, "start_date": "2027-13-45"}, P)
check("a bad date is refused with the screen's own code (E-REPEAT-002)", "_err" in r and "E-REPEAT-002" in r["_err"], r)
r = call("plan_repeat", {"workspace_id": PLAN, "journey_architecture_id": ARCH, "start_date": "2027-09-08"}, P)
check("a start inside the source plan is refused (E-REPEAT-003)", "_err" in r and "E-REPEAT-003" in r["_err"], r)
r = call("plan_repeat", {"workspace_id": PLAN, "journey_architecture_id": ARCH, "periods": 9}, P)
check("more than 8 periods is refused (E-REPEAT-010)", "_err" in r and "E-REPEAT-010" in r["_err"], r)

r = call("plan_repeat", {"workspace_id": PLAN, "journey_architecture_id": ARCH, "start_date": D(0), "create": True}, P)
check("draft: a new plan is made, mode 'draft', not published", r.get("mode") == "draft" and r.get("workspace_id", 0) > 0 and r.get("published") is False, r)
check("the answer says it is a draft and a person must review and Publish to live",
      "DRAFT" in r.get("message", "") and "Publish to live" in r.get("message", "") and "needs review" in r.get("message", ""), r.get("message"))
check("the answer leads with what was left out", r.get("message", "").startswith("Left out ("), r.get("message"))
new_ws = r.get("workspace_id")
tool_counts = r.get("counts")
if new_ws:
    b = board(new_ws)
    n_slots = (tool_counts or {}).get("slots", {}).get("placed", 0) + (tool_counts or {}).get("slots", {}).get("backlog", 0)
    check("every copied slot (placed or in the backlog) is marked needs review", len(b.get("reviews", [])) == n_slots and n_slots > 0, (len(b.get("reviews", [])), n_slots))
    check("every day of the new plan is a draft", all(t.get("status") == "draft" for t in b.get("timelines", [])))
r2 = call("plan_repeat", {"workspace_id": PLAN, "journey_architecture_id": ARCH, "start_date": D(0), "create": True}, P)
check("the same date again answers 'exists' and makes nothing", r2.get("mode") == "exists" and r2.get("workspace_id") == new_ws, r2)

# T-07-2: the same counts as a repeat made from the screen (another date, same function)
st, s = http("POST", f"{PL}/workspace/{PLAN}/repeat", {"start_date": D(1), "name": "AITOOL fx screen copy %d (safe to delete)" % __import__("time").time()}, P)
check("T-07-2 the draft matches a repeat made from the screen (same counts)", st == 200 and s.get("counts") == tool_counts, (s.get("counts"), tool_counts))
st, pv = http("POST", f"{PL}/workspace/{PLAN}/repeat-preview", {"start_date": D(2)}, P)
check("the screen's preview and the tool's preview give the same counts", st == 200 and pv.get("counts") == prev_counts, (pv.get("counts"), prev_counts))

print("\n== as the AI member ==")
r = call("plan_repeat", {"workspace_id": PLAN, "journey_architecture_id": ARCH}, AI_TOKEN)
check("the AI may preview a plan in its list", r.get("mode") == "preview" and "Preview only" in r.get("message", ""), r)
r = call("plan_repeat", {"workspace_id": OTHER, "journey_architecture_id": ARCH}, AI_TOKEN)
check("T-07-3 a plan outside its list is refused like one that does not exist", "_err" in r and "not found" in r["_err"].lower(), r)
r = call("plan_repeat", {"workspace_id": OTHER, "journey_architecture_id": ARCH, "start_date": D(3), "create": True}, AI_TOKEN)
check("T-07-3 and cannot be drafted either", "_err" in r and "not found" in r["_err"].lower(), r)
r = call("plan_repeat", {"workspace_id": PLAN, "journey_architecture_id": ARCH, "start_date": D(3), "create": True}, AI_TOKEN)
check("the AI can draft a repeat of a plan in its list", r.get("mode") == "draft" and r.get("workspace_id", 0) > 0, r)
ai_ws1 = r.get("workspace_id")
r = call("plan_repeat", {"workspace_id": PLAN, "journey_architecture_id": ARCH, "start_date": D(4), "create": True}, AI_TOKEN)
check("a second draft is the AI's second write", r.get("mode") == "draft", r)
made_more = 0
r = {}
for k in range(5, 10):  # the hourly cap was set to (writes so far + 3): keep writing until it says no
    r = call("plan_repeat", {"workspace_id": PLAN, "journey_architecture_id": ARCH, "start_date": D(k), "create": True}, AI_TOKEN)
    if "_err" in r:
        break
    made_more += 1
check("T-07-5 the hourly cap stops the AI after exactly its allowance (E-AIM-050)", "_err" in r and "E-AIM-050" in r["_err"] and made_more <= 3, (made_more, r))
r = call("plan_repeat", {"workspace_id": PLAN, "journey_architecture_id": ARCH, "start_date": D(5)}, AI_TOKEN)
check("a preview is a read: it still works at the write cap", r.get("mode") == "preview", r)
if ai_ws1:
    b = board(ai_ws1)
    check("the AI's draft has every copied slot marked needs review, and no day is published", len(b.get("reviews", [])) > 0 and all(t.get("status") == "draft" for t in b.get("timelines", [])))

print("\nnew plan (person):", new_ws, "| AI plans:", ai_ws1)
print("\n%d/%d passed" % (sum(res), len(res)))
sys.exit(0 if all(res) else 1)
