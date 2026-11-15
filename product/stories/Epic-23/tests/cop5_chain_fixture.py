"""COP-5 / COP-7-06 - builds ONE real chain in TEST account 13, business 49, through the product's own
endpoints, as test admin usr2-q:
  map (2 stages) -> Publish version -> plan -> accept map -> job -> two people on the plan (the test
  admin, and the copilot as an AI) -> a day each -> schedule -> Publish to live -> start/finish -> variance.
State is kept in a temp file so a re-run continues where it stopped. Never prints a token.
Usage: python cop5_chain_fixture.py <magic_token | ->   (prerequisite: publish_gate flag + planning/execution grants)
"""
import datetime, json, os, sys, tempfile, uuid
from cop5_lib import *
T = token(sys.argv)
STATE = os.path.join(tempfile.gettempdir(), "cop5_chain_state.json")
S = json.load(open(STATE)) if os.path.exists(STATE) else {}
def save(): json.dump(S, open(STATE, "w"))
ARCH = 49; ADMIN_USER = 22; COPILOT_USER = 26
TODAY = datetime.datetime.utcnow().strftime("%Y-%m-%d")

# ---- 1. map ---------------------------------------------------------------
if "map" not in S:
    c, b = req("POST", JM + "/journey_map/create_draft", {"title": "COP-5 chain fixture (safe to delete)", "journey_architecture_id": ARCH}, T)
    assert c == 200, short(b); S["map"] = b["journey_map"]["id"]; save()
MAP = S["map"]
c, bundle = req("GET", JM + f"/journey_map/load_bundle/{MAP}", None, T)
assert c == 200, short(bundle)
stages = sorted(bundle["stages"], key=lambda s: s["display_order"])
for st in stages[2:]:
    c, b = req("DELETE", JM + f"/journey_stage/remove/{st['id']}", None, T); print("remove stage", st["key"], c, "" if c == 200 else short(b, 200))
lenses = bundle["lenses"]
crew = next((l for l in lenses if l["label"] == "Crew"), None)
if not crew:
    c, b = req("POST", JM + f"/journey_map/../journey_lens/add/{MAP}".replace("journey_map/../", ""), {"label": "Crew", "actor_type": "internal"}, T)
    assert c == 200, short(b); print("lens add keys", list(b.keys()))
c, bundle = req("GET", JM + f"/journey_map/load_bundle/{MAP}", None, T)
stages = sorted(bundle["stages"], key=lambda s: s["display_order"]); lenses = bundle["lenses"]
crew = next(l for l in lenses if l["label"] == "Crew")
c, b = req("PATCH", JM + f"/journey_lens_planned_work/{crew['id']}", {"does_planned_work": True}, T); print("planned work", c, "" if c == 200 else short(b, 300))
names = ["Prepare", "Deliver"]
for i, st in enumerate(stages):
    c, b = req("PATCH", JM + f"/journey_stage/update/{st['id']}", {"label": names[i], "owner_lens_id": crew["id"]}, T); print("stage", names[i], c, "" if c == 200 else short(b, 300))
    cell = next(x for x in bundle["cells"] if x["stage"] == st["id"] and x["lens"] == crew["id"])
    c, b = req("PATCH", JM + f"/journey_cell/update/{cell['id']}", {"content": names[i] + " the order", "actor_fields": {"task_objective": names[i] + " the order", "success_criteria": names[i] + " is checked off"}, "time_duration_value": 30, "time_duration_unit": "minutes"}, T)
    print("cell", names[i], c, "" if c == 200 else short(b, 300))
if "version" not in S:
    c, b = req("POST", JM + f"/journey_map/{MAP}/publish", {}, T)
    print("publish version", c, short(b.get("gate", b), 600) if c != 200 or not b.get("map_version") else "ok")
    assert c == 200 and b.get("map_version"), "Publish version did not write a version"
    S["version"] = b["map_version"]["id"]; save()
check("a published map version exists", S.get("version"))

# ---- 2. plan, job ----------------------------------------------------------
if "plan" not in S:
    c, b = req("POST", PL + "/workspace", {"name": "COP-5 chain plan (safe to delete)"}, T); assert c == 200, short(b)
    S["plan"] = b["workspace"]["id"]; save()
PLAN = S["plan"]
c, b = req("POST", PL + f"/workspace/{PLAN}/map", {"map_ids": [MAP]}, T); check("plan accepts the map", c == 200, short(b))
if "job" not in S:
    c, b = req("POST", PL + "/work_item", {"workspace_id": PLAN, "journey_map_id": MAP, "title": "COP-5 chain job"}, T); assert c == 200, short(b)
    S["job"] = b["work_item"]["id"]; print("job tasks", b.get("task_count"), short(b.get("skipped_stages"), 200)); save()
JOB = S["job"]
c, job = req("GET", PL + f"/work_item/{JOB}", None, T); assert c == 200, short(job)
tasks = job.get("tasks") or []
print("task sample", short(tasks[:1], 500))
check("the job has two tasks", len(tasks) == 2, len(tasks))

# ---- 3. people -------------------------------------------------------------
def agent(key, name, kind, user_id):
    if key not in S:
        c, b = req("POST", PL + f"/workspace/{PLAN}/agent", {"name": name, "kind": kind, "daily_capacity_hours": 8}, T); assert c == 200, short(b)
        a = b.get("agent") or b; S[key] = a["id"]; save()
        c, b = req("PATCH", PL + f"/agent/{S[key]}", {"user_id": user_id}, T); print("link", name, c, "" if c == 200 else short(b, 300))
    return S[key]
A_PERSON = agent("agent_person", "Test admin", "person", ADMIN_USER)
A_AI = agent("agent_ai", "Copilot", "ai", COPILOT_USER)

def day(key, agent_id):
    if key not in S:
        c, b = req("POST", PL + f"/workspace/{PLAN}/timeline", {"agent_id": agent_id, "planned_date": TODAY}, T); assert c == 200, short(b)
        S[key] = b["timeline"]["id"]; save()
    return S[key]
D_PERSON = day("day_person", A_PERSON); D_AI = day("day_ai", A_AI)

# ---- 4. schedule: task 1 -> the person's day, task 2 -> the copilot's day ----
def tid(t): return t.get("id") or t.get("work_task_id")
if "sched" not in S:
    c, b = req("POST", PL + f"/work_task/{tid(tasks[0])}/schedule", {"timeline_id": D_PERSON}, T); print("schedule 1", c, "" if c == 200 else short(b, 300))
    c2, b2 = req("POST", PL + f"/work_task/{tid(tasks[1])}/schedule", {"timeline_id": D_AI}, T); print("schedule 2", c2, "" if c2 == 200 else short(b2, 300))
    if c == 200 and c2 == 200: S["sched"] = True; S["task_person"] = tid(tasks[0]); S["task_ai"] = tid(tasks[1]); save()
check("both tasks are scheduled", S.get("sched"))

# ---- 5. Publish to live (a person does this - never the copilot) -------------
for key, d in (("live_person", D_PERSON), ("live_ai", D_AI)):
    if key not in S:
        c, b = req("POST", PL + f"/timeline/{d}/publish", {}, T); print("publish to live", key, c, "" if c == 200 else short(b, 300))
        if c == 200: S[key] = b["publication"]["id"]; save()
check("both days are published to live", S.get("live_person") and S.get("live_ai"))

# ---- 6. the person starts and finishes their task --------------------------
if "person_done" not in S:
    c, b = req("POST", PL + f"/work_task/{S['task_person']}/event", {"event_type": "started", "client_event_id": str(uuid.uuid4())}, T); print("start", c, short(b, 200) if c != 200 else b.get("to"))
    c2, b2 = req("POST", PL + f"/work_task/{S['task_person']}/event", {"event_type": "completed", "client_event_id": str(uuid.uuid4())}, T); print("finish", c2, short(b2, 200) if c2 != 200 else b2.get("to"))
    if c == 200 and c2 == 200: S["person_done"] = True; save()
check("the person's task is done", S.get("person_done"))

# ---- 7. variance -------------------------------------------------------------
c, v = req("GET", PL + f"/variance/work_item/{JOB}", None, T)
check("variance report answers", c == 200 and v.get("task_count") == 2, short(v))
print("variance", short(v, 1200))
print("STATE", json.dumps(S))
done()
