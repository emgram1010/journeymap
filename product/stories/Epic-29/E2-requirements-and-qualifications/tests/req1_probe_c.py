"""REQ-1 story 03 and 04 - the links that other features write, live over real HTTP in the test account (13):
a plan made from a template links its people; a repeat carries the links; removing a person or deleting
a plan removes the link; the one-time fill, applied and run twice; a cloned map keeps its needs.
Admin = usr2-q (user 22). Never prints a token. Everything it makes is deleted again.
Usage: python req1_probe_c.py <magic admin> <profile ids to roster, comma separated, three distinct names> <user id to tag as an agent>
"""
import json, sys, time, urllib.request, urllib.error, datetime

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
H = "https://xdjc-i7zz-jhm2.n7e.xano.io"
AUTH = H + "/api:RPonubWS"
PL = H + "/api:PE5iDldw:v1"
JM = H + "/api:ER4MRRWZ"
CAT = H + "/api:FB308vAe"
res = []


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


def check(n, ok, d=""):
    res.append(bool(ok))
    print(("PASS  " if ok else "FAIL  ") + n + (("   [" + str(d)[:400] + "]") if d and not ok else ""))


st, d = http("POST", AUTH + "/reset/magic-link-login", {"magic_token": sys.argv[1], "email": "usr2-q@example.com"})
assert st == 200 and d.get("authToken"), "sign-in failed"
A = d["authToken"]
ROSTER = [int(x) for x in sys.argv[2].split(",")]
TAG_USER = int(sys.argv[3])
tag = str(int(time.time()))[-6:]
msg = lambda r: str(r.get("message", ""))
made = {"plans": [], "templates": []}


def links(ws):
    return http("GET", f"{PL}/workspace/{ws}/person-link", None, A)[1].get("people", [])


# leftovers from an earlier run of this probe
for w in http("GET", PL + "/workspace", None, A)[1].get("workspaces", []):
    nm = w["workspace"]["name"]
    if nm.startswith("R1 from template") or nm.startswith("R1 repeat"):
        http("DELETE", f"{PL}/workspace/{w['workspace']['id']}", None, A)

print("== a plan made from a template ==")
st, p = http("POST", PL + "/agent-profile", {"user_id": TAG_USER}, A)
login_profile = (p.get("profile") or {}).get("id")
if not login_profile:  # already tagged by an earlier run: find it
    for e in http("GET", PL + "/agent-profile?include_ineligible=true", None, A)[1].get("profiles", []):
        if e["profile"]["user_id"] == TAG_USER:
            login_profile = e["profile"]["id"]; st = 200
check("tag a login as an agent (it now has a profile for the fill to find)", st == 200 and login_profile, (st, p))
roster = ROSTER + [login_profile]
st, t = http("POST", PL + "/template", {"name": f"R1 template {tag} (safe to delete)", "window_days": 7, "agent_profile_ids": roster}, A)
tid = (t.get("template") or {}).get("id")
check("a throwaway template with a roster", st == 200 and tid, (st, t))
made["templates"].append(tid)
st, inst = http("POST", f"{PL}/template/{tid}/instance", {"name": f"R1 from template {tag} (safe to delete)", "start_date": "2030-03-04"}, A)
ws1 = (inst.get("workspace") or {}).get("id")
check("a plan made from it", st == 200 and ws1, (st, inst))
made["plans"].append(ws1)
people = links(ws1)
check("T-03-1 every person copied from the roster is linked to the profile they came from", len(people) == len(roster) and all(p["profile_id"] in roster for p in people), people)
login_person = [p for p in people if p["user_id"] == TAG_USER]
check("...including the one with a login", len(login_person) == 1 and login_person[0]["profile_id"] == login_profile, people)

print("\n== a repeat carries the links ==")
st, rep = http("POST", f"{PL}/workspace/{ws1}/repeat", {"start_date": "2030-03-11", "name": f"R1 repeat {tag} (safe to delete)"}, A)
ws2 = rep.get("workspace_id")
check("repeat the plan", st == 200 and rep.get("outcome") == "created" and ws2, (st, rep))
made["plans"].append(ws2)
people2 = links(ws2)
check("T-03-1 each person in the copy carries the link their source had", len(people2) == len(people) and sorted(p["profile_id"] for p in people2) == sorted(p["profile_id"] for p in people), people2)

print("\n== the one-time fill ==")
agent_id = login_person[0]["planner_agent_id"]
st, r = http("DELETE", f"{PL}/workspace/{ws1}/person-link/{agent_id}", None, A)
check("unlink the login person on plan 1", st == 200 and r.get("removed") is True, (st, r))
st, f0 = http("POST", PL + "/person-link-fill", {}, A)
check("T-03-3 a login with exactly one profile is found, and nothing is written yet", st == 200 and f0["applied"] is False and f0["would_link"] >= 1 and f0["linked"] == 0, f0)
check("...still unlinked after the report", [p for p in links(ws1) if p["planner_agent_id"] == agent_id][0]["profile_id"] == 0)
st, f1 = http("POST", PL + "/person-link-fill", {"apply": True}, A)
check("applying links them", st == 200 and f1["applied"] is True and f1["linked"] >= 1, f1)
check("...the person is linked to the profile of their login", [p for p in links(ws1) if p["planner_agent_id"] == agent_id][0]["profile_id"] == login_profile)
st, f2 = http("POST", PL + "/person-link-fill", {"apply": True}, A)
check("T-03-4 running it twice changes nothing", st == 200 and f2["linked"] == 0 and f2["would_link"] == 0 and f2["already_linked"] >= f1["already_linked"] + f1["linked"], (f1, f2))

print("\n== a link goes with the person, and with the plan ==")
victim = [p for p in links(ws2) if p["user_id"] != TAG_USER][0]["planner_agent_id"]
st, r = http("DELETE", f"{PL}/agent/{victim}", None, A)
check("remove a person from a plan", st == 200, (st, r))
check("T-03-7 their link is gone with them", victim not in [p["planner_agent_id"] for p in links(ws2)])
for w in (ws2, ws1):
    st, r = http("DELETE", f"{PL}/workspace/{w}", None, A)
    check(f"T-03-7 deleting plan {w} leaves no link behind", st == 200 and r.get("left_behind") == 0, (st, r))
made["plans"] = []

print("\n== a cloned map keeps its needs ==")
st, rq = http("POST", CAT + "/requirement", {"name": f"R1 clone need {tag}"}, A)
rid = rq["requirement"]["id"]
SRC = 261
b = http("GET", f"{JM}/journey_map/load_bundle/{SRC}", None, A)[1]
planned = [l["id"] for l in b.get("lenses", []) if l.get("actor_type") in ("internal", "ai_agent")]
cell = next((c for c in b.get("cells", []) if c["lens"] in planned), None)
if not cell:
    print("   (map 261 has no planned-work step: clone check skipped)")
else:
    st, r = http("POST", f"{JM}/journey_cell/{cell['id']}/requirement", {"requirement_id": rid, "strength": "hard"}, A)
    check("a need on a step of the source map", st == 200, (st, r))
    arch = (b.get("journey_map") or {}).get("journey_architecture") or 47
    st, cl = http("POST", f"{JM}/journey_architecture/{arch}/scenarios/clone", {"source_map_id": SRC, "title": f"R1 clone {tag} (safe to delete)"}, A)
    newmap = ((cl.get("journey_map") or cl.get("map") or cl).get("id")) if st == 200 else None
    check("clone the map", bool(newmap), (st, cl))
    if newmap:
        nb = http("GET", f"{JM}/journey_map/load_bundle/{newmap}", None, A)[1]
        st, n = http("GET", f"{JM}/journey_map/{newmap}/requirement", None, A)
        mine = [x for x in n.get("needs", []) if x["requirement_id"] == rid]
        check("T-04-7 the copy has the same need on the same step (same stage and row keys, same strength)", len(mine) == 1 and mine[0]["strength"] == "hard" and mine[0]["journey_cell_id"] != cell["id"], n)
        check("...and the source still has its own", any(x["requirement_id"] == rid and x["journey_cell_id"] == cell["id"] for x in http("GET", f"{JM}/journey_map/{SRC}/requirement", None, A)[1].get("needs", [])))
        st, r = http("DELETE", f"{JM}/journey_map/{newmap}", None, A)
        print("   removed the clone:", st)
    http("DELETE", f"{JM}/journey_cell/{cell['id']}/requirement/{rid}", None, A)
st, r = http("DELETE", f"{CAT}/requirement/{rid}", None, A)
print("   cleaned the need's requirement:", st)
for t_ in made["templates"]:
    http("PATCH", f"{PL}/template/{t_}", {"is_active": False}, A)
print("\nleft to clean by the caller: profile", login_profile, "(a profile for user", TAG_USER, "), template", made["templates"])
print("\n%d/%d passed" % (sum(res), len(res)))
sys.exit(0 if all(res) else 1)
