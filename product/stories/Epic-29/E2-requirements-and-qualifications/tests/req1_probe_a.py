"""REQ-1 stories 01-03 - live probe over real HTTP in the test account (13): the requirement list, what a
person holds, and the plan-person link. Admin = usr2-q (user 22), member = usr2-p (user 21).
Never prints a token. Every row it makes is named "R1 ... (safe to delete)" and is cleaned up by the
caller (the probe prints what it made).
Usage: python req1_probe_a.py <magic admin> <magic member> <foreign requirement id> <foreign profile id>
  foreign requirement / profile = rows that belong to ANOTHER account (the caller inserts a throwaway
  requirement for a non-existent account, and names an existing profile of the founder's account).
"""
import json, sys, time, datetime, threading, urllib.request, urllib.error

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
H = "https://xdjc-i7zz-jhm2.n7e.xano.io"
AUTH = H + "/api:RPonubWS"
PL = H + "/api:PE5iDldw:v1"
CAT = H + "/api:FB308vAe"
res = []
made = {"requirements": [], "profiles": [], "plans": []}


def http(method, url, body=None, tok=None):
    r = urllib.request.Request(url, data=json.dumps(body).encode() if body is not None else None, method=method)
    r.add_header("Content-Type", "application/json")
    if tok:
        r.add_header("Authorization", "Bearer " + tok)
    try:
        raw = urllib.request.urlopen(r, timeout=120).read()
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


def login(magic, email):
    st, d = http("POST", AUTH + "/reset/magic-link-login", {"magic_token": magic, "email": email})
    assert st == 200 and d.get("authToken"), "sign-in failed for " + email
    return d["authToken"]


msg = lambda r: str(r.get("message", ""))
A = login(sys.argv[1], "usr2-q@example.com")
M = login(sys.argv[2], "usr2-p@example.com")
FOREIGN_REQ, FOREIGN_PROFILE = int(sys.argv[3]), int(sys.argv[4])
tag = str(int(time.time()))[-6:]


def lst(tok=A, archived=False):
    return http("GET", CAT + "/requirement" + ("?include_archived=true" if archived else ""), None, tok)[1].get("requirements", [])


def add(name, tok=A, **kw):
    st, r = http("POST", CAT + "/requirement", {"name": name, **kw}, tok)
    if st == 200 and r.get("outcome") == "created":
        made["requirements"].append(r["requirement"]["id"])
    return st, r


print("== story 01: one list ==")
st, r = http("GET", CAT + "/requirement", None, M)
check("a member can read the list", st == 200)
st, r = add(f"R1 member {tag}", M)
check("a member cannot add (E-USR-001)", st in (400, 403) and "E-USR-001" in msg(r), (st, r))

base = f"R1 Forklift {tag}"
st, r = add(base)
check("T-01-1 add a requirement", st == 200 and r["outcome"] == "created" and r["requirement"]["name"] == base, r)
fid = (r.get("requirement") or {}).get("id")
st, r2 = add(base.lower())
check("T-01-2 lower case is the same requirement (nothing created)", st == 200 and r2["outcome"] == "exists" and r2["requirement"]["id"] == fid, r2)
st, r2 = add("  " + base.upper() + "  ")
check("T-01-2 spaces and upper case too", st == 200 and r2["outcome"] == "exists" and r2["requirement"]["id"] == fid, r2)
st, r2 = add(base.replace("R1 ", "R1    "))
check("T-01-2 inner spaces collapse", st == 200 and r2["outcome"] == "exists", r2)
n_before = len(lst())
st, r2 = add(base + " licence")
check("a near match is SHOWN and nothing is created", st == 200 and r2["outcome"] == "similar" and any(m["id"] == fid for m in r2["matches"]) and len(lst()) == n_before, r2)
st, r2 = add(base + " licence", confirm_similar=True)
check("...until the caller asks again", st == 200 and r2["outcome"] == "created", r2)
lic = (r2.get("requirement") or {}).get("id")

for label, bad, code in [("empty", "   ", "E-REQ-001"), ("61 characters", "x" * 61, "E-REQ-001"), ("HTML", "<b>Forklift</b>", "E-REQ-002")]:
    st, r2 = add(bad)
    check(f"T-01-3 a bad name ({label}) is refused with its code", st == 400 and code in msg(r2), (st, r2))
st, r2 = add(f"R1 Q&A < 3 {tag}")
check("a lone < or & is not HTML", st == 200 and r2["outcome"] in ("created", "similar"), r2)
if r2.get("outcome") == "similar":
    add(f"R1 Q&A < 3 {tag}", confirm_similar=True)

st, r2 = http("PATCH", f"{CAT}/requirement/{fid}", {"name": base + " (counterbalance)"}, A)
check("T-01-1 rename", st == 200 and r2["requirement"]["name"].endswith("(counterbalance)"), r2)
check("a rename shows everywhere at once", any(x["id"] == fid and x["name"].endswith("(counterbalance)") for x in lst()))
st, r2 = http("PATCH", f"{CAT}/requirement/{fid}", {"name": base + " licence"}, A)
check("renaming onto an existing name is refused (E-REQ-003)", st == 400 and "E-REQ-003" in msg(r2), (st, r2))
st, r2 = http("PATCH", f"{CAT}/requirement/{fid}", {"name": "  "}, A)
check("renaming to nothing is refused (E-REQ-001)", st == 400 and "E-REQ-001" in msg(r2), (st, r2))
st, r2 = http("PATCH", f"{CAT}/requirement/{fid}", {"description": "Counterbalance trucks"}, A)
check("a description alone changes only the description", st == 200 and r2["requirement"]["description"] == "Counterbalance trucks" and r2["requirement"]["name"].endswith("(counterbalance)"), r2)
st, r2 = http("PATCH", f"{CAT}/requirement/{fid}", {"name": base + " (counterbalance)"}, M)
check("a member cannot rename", st in (400, 403) and "E-USR-001" in msg(r2), (st, r2))

st, r2 = http("POST", f"{CAT}/requirement/{lic}/archive", {"is_archived": True}, A)
check("T-06 archive hides it from the default list", st == 200 and lic not in [x["id"] for x in lst()])
check("...and 'show archived' lists it", lic in [x["id"] for x in lst(archived=True)])
st, r2 = http("POST", f"{CAT}/requirement/{lic}/archive", {"is_archived": False}, A)
check("restore brings it back", st == 200 and lic in [x["id"] for x in lst()])

print("   (parallel adds)")
pname = f"R1 Parallel {tag}"
outs = []
def worker():
    outs.append(http("POST", CAT + "/requirement", {"name": pname}, A))
ts = [threading.Thread(target=worker) for _ in range(4)]
[t.start() for t in ts]; [t.join() for t in ts]
created = [o for o in outs if o[0] == 200 and o[1].get("outcome") == "created"]
exists = [o for o in outs if o[0] == 200 and o[1].get("outcome") == "exists"]
for o in created:
    made["requirements"].append(o[1]["requirement"]["id"])
check("T-01-5 four parallel adds of one name leave exactly ONE requirement", len(created) == 1 and len(exists) == 3 and len([x for x in lst() if x["name"] == pname]) == 1, [(o[0], o[1].get("outcome")) for o in outs])

st, r2 = http("PATCH", f"{CAT}/requirement/{FOREIGN_REQ}", {"name": "stolen"}, A)
check("T-01-7 another account's requirement: rename is 'not found'", st == 404, (st, r2))
st, r2 = http("DELETE", f"{CAT}/requirement/{FOREIGN_REQ}", None, A)
check("...delete too", st == 404, (st, r2))
st, r2 = http("GET", f"{CAT}/requirement/{FOREIGN_REQ}/holders", None, A)
check("...and its holders", st == 404, (st, r2))
check("...and it is not in my list", FOREIGN_REQ not in [x["id"] for x in lst(archived=True)])

print("\n== story 02: who holds what ==")
st, p = http("POST", PL + "/agent-profile", {"name": f"R1 Holder {tag} (safe to delete)"}, A)
check("a profile to hold things (an AI agent, no login)", st == 200 and p.get("profile", {}).get("id"), (st, p))
prof = p["profile"]["id"]; made["profiles"].append(prof)
H_ = f"{PL}/agent-profile/{prof}/requirement"

st, r = http("POST", H_, {"requirement_id": fid, "held_until": "2027-03-31"}, A)
check("T-02-1 record a holding with an end date", st == 200 and r.get("created") is True and r.get("held_until") == "2027-03-31", (st, r))
st, g = http("GET", H_ + "?on_date=2027-03-31", None, A)
check("T-02-2 on the last day it is held", st == 200 and g["holdings"][0]["held"] is True, g)
st, g = http("GET", H_ + "?on_date=2027-04-01", None, A)
check("T-02-2 the day after it is not", g["holdings"][0]["held"] is False, g)
st, g = http("GET", H_ + "?on_date=2027-03-01", None, A)
check("T-02-4 30 days before it 'ends soon' with the days left", g["holdings"][0]["ends_soon"] is True and g["holdings"][0]["days_left"] == 30, g)
st, g = http("GET", H_ + "?on_date=2027-02-28", None, A)
check("T-02-4 31 days before it does not", g["holdings"][0]["ends_soon"] is False, g)
st, r = http("POST", H_, {"requirement_id": fid, "held_until": "2028-01-01"}, A)
check("record it twice: the end date changes, not an error", st == 200 and r.get("created") is False and r.get("held_until") == "2028-01-01", (st, r))
st, r = http("POST", H_, {"requirement_id": fid, "held_until": ""}, A)
st, g = http("GET", H_ + "?on_date=2099-01-01", None, A)
check("T-02-3 an empty date means no end", g["holdings"][0]["held"] is True and g["holdings"][0]["held_until"] == "", g)
st, r = http("POST", H_, {"requirement_id": fid}, A)
st, g = http("GET", H_ + "?on_date=2099-01-01", None, A)
check("T-02-3 a date left out means no end too", g["holdings"][0]["held"] is True and g["holdings"][0]["held_until"] == "", g)
st, r = http("POST", H_, {"requirement_id": fid, "held_until": "2027-13-45"}, A)
check("a date that does not exist is refused (E-REQ-012)", st == 400 and "E-REQ-012" in msg(r), (st, r))
st, r = http("POST", H_, {"requirement_id": fid, "held_until": "next week"}, A)
check("a date in the wrong shape is refused too", st == 400 and "E-REQ-012" in msg(r), (st, r))
st, r = http("POST", H_, {"requirement_id": FOREIGN_REQ}, A)
check("T-02-7 another account's requirement cannot be recorded", st == 404, (st, r))
st, r = http("POST", f"{PL}/agent-profile/{FOREIGN_PROFILE}/requirement", {"requirement_id": fid}, A)
check("T-02-7 another account's profile cannot be recorded on", st == 404, (st, r))
st, r = http("GET", f"{PL}/agent-profile/{FOREIGN_PROFILE}/requirement", None, A)
check("T-02-7 ...or read", st == 404, (st, r))
st, r = http("POST", H_, {"requirement_id": fid, "held_until": "2027-03-31"}, M)
check("a member cannot record a holding (E-USR-001)", st in (400, 403) and "E-USR-001" in msg(r), (st, r))
st, g = http("GET", H_, None, M)
check("a member can read what a person holds", st == 200 and len(g["holdings"]) == 1, (st, g))

http("POST", f"{CAT}/requirement/{lic}/archive", {"is_archived": True}, A)
st, r = http("POST", H_, {"requirement_id": lic}, A)
check("T-02-5 an archived requirement cannot be newly recorded (E-REQ-011)", st == 400 and "E-REQ-011" in msg(r), (st, r))
st, r = http("POST", H_, {"requirement_id": fid, "held_until": "2027-06-30"}, A)
http("POST", f"{CAT}/requirement/{lic}/archive", {"is_archived": False}, A)
http("POST", H_, {"requirement_id": lic, "held_until": "2027-06-30"}, A)
http("POST", f"{CAT}/requirement/{lic}/archive", {"is_archived": True}, A)
st, r = http("POST", H_, {"requirement_id": lic, "held_until": "2027-07-31"}, A)
check("...but an existing holding of an archived requirement can still change", st == 200 and r.get("created") is False, (st, r))
st, g = http("GET", H_, None, A)
check("...and it still shows, marked archived", any(h["requirement_id"] == lic and h["archived"] for h in g["holdings"]), g)
http("POST", f"{CAT}/requirement/{lic}/archive", {"is_archived": False}, A)

st, hs = http("GET", f"{CAT}/requirement/{fid}/holders?on_date=2027-04-01", None, M)
check("see it from the other side: who holds it", st == 200 and any(h["agent_profile_id"] == prof for h in hs["holders"]), hs)

reqs = {x["id"]: x for x in lst()}
check("the list counts people who hold each requirement", reqs[fid]["held_by_people"] == 1 and reqs[lic]["held_by_people"] == 1, (reqs[fid], reqs[lic]))
st, r = http("DELETE", f"{CAT}/requirement/{fid}", None, A)
check("T-01-4 delete is refused while a person holds it, and says how many (E-REQ-004)", st == 400 and "E-REQ-004" in msg(r) and "1 person" in msg(r), (st, r))
st, r = http("DELETE", H_ + f"/{fid}", None, M)
check("a member cannot remove a holding", st in (400, 403), (st, r))
st, r = http("DELETE", H_ + f"/{fid}", None, A)
check("T-02-1 remove a holding", st == 200 and r.get("removed") is True, (st, r))
st, r = http("DELETE", H_ + f"/{fid}", None, A)
check("removing one that is not held is not an error", st == 200 and r.get("removed") is False, (st, r))
http("DELETE", H_ + f"/{lic}", None, A)
st, r = http("DELETE", f"{CAT}/requirement/{lic}", None, A)
check("T-01-4 delete works once nothing uses it", st == 200, (st, r))
made["requirements"] = [i for i in made["requirements"] if i != lic]

print("\n== story 03: a person on a plan and their profile ==")
st, w = http("POST", PL + "/workspace", {"name": f"R1 plan {tag} (safe to delete)", "planning_window_start": "2030-02-04", "planning_window_end": "2030-02-10"}, A)
check("a throwaway plan", st == 200 and (w.get("workspace") or {}).get("id"), (st, w))
ws = w["workspace"]["id"]; made["plans"].append(ws)
ids = {}
for nm, kind in [(f"R1 Ana {tag}", "person"), (f"R1 Bob {tag}", "person"), (f"R1 Bot {tag}", "ai")]:
    st, a = http("POST", f"{PL}/workspace/{ws}/agent", {"name": nm, "kind": kind}, A)
    ids[nm] = (a.get("agent") or {}).get("id")
check("three people on the plan, none from a profile", all(ids.values()), ids)
ana, bob, bot = [ids[k] for k in ids]
PLK = f"{PL}/workspace/{ws}/person-link"
st, pl = http("GET", PLK, None, M)
check("T-03-6 a member can read it; everyone shows 'no profile'", st == 200 and len(pl["people"]) == 3 and all(p["profile_id"] == 0 for p in pl["people"]), pl)

st, ap = http("POST", PL + "/agent-profile", {"name": f"R1 Ana {tag}"}, A)
ana_profile = ap["profile"]["id"]; made["profiles"].append(ana_profile)
st, pl = http("GET", PLK, None, A)
row = [p for p in pl["people"] if p["planner_agent_id"] == ana][0]
check("a profile with exactly the same name is OFFERED, never linked", row["profile_id"] == 0 and row["name_match_profile_id"] == ana_profile and row["name_match_count"] == 1, row)
st, ap2 = http("POST", PL + "/agent-profile", {"name": f"R1 Bob {tag}"}, A)
st, ap3 = http("POST", PL + "/agent-profile", {"name": f"R1 Bob {tag}"}, A)
made["profiles"] += [ap2["profile"]["id"], ap3["profile"]["id"]]
st, pl = http("GET", PLK, None, A)
row = [p for p in pl["people"] if p["planner_agent_id"] == bob][0]
check("a name shared by two profiles is only reported, with its count", row["name_match_profile_id"] == 0 and row["name_match_count"] == 2, row)

st, r = http("POST", PLK, {"planner_agent_id": ana, "agent_profile_id": ana_profile}, M)
check("a member cannot link (E-USR-001)", st in (400, 403) and "E-USR-001" in msg(r), (st, r))
st, r = http("POST", PLK, {"planner_agent_id": ana, "agent_profile_id": ana_profile}, A)
check("an admin links by hand", st == 200 and r.get("result") == "created", (st, r))
st, r = http("POST", PLK, {"planner_agent_id": ana, "agent_profile_id": ana_profile}, A)
check("linking again to the same profile changes nothing", st == 200 and r.get("result") == "same", (st, r))
st, r = http("POST", PLK, {"planner_agent_id": ana, "agent_profile_id": FOREIGN_PROFILE}, A)
check("T-03-5 a profile from another account cannot be linked", st == 404, (st, r))
st, r = http("POST", PLK, {"planner_agent_id": 999999999, "agent_profile_id": ana_profile}, A)
check("a person who is not on this plan is refused", st == 404, (st, r))
st, pl = http("GET", PLK, None, A)
row = [p for p in pl["people"] if p["planner_agent_id"] == ana][0]
check("T-03-6 the people list returns the link", row["profile_id"] == ana_profile and "R1 Ana" in row["profile_name"], row)
st, r = http("POST", PLK + "/create-profile", {"planner_agent_id": bob}, M)
check("a member cannot make a profile for someone", st in (400, 403) and "E-USR-001" in msg(r), (st, r))
st, r = http("POST", PLK + "/create-profile", {"planner_agent_id": bot}, A)
check("'Create profile' makes one for a person with no login, and links them", st == 200 and r.get("made_new_profile") is True, (st, r))
made["profiles"].append(r.get("agent_profile_id"))
st, pl = http("GET", PLK, None, A)
row = [p for p in pl["people"] if p["planner_agent_id"] == bot][0]
check("...they now show a profile", row["profile_id"] == r.get("agent_profile_id") and row["profile_id"] != 0, row)
st, r = http("DELETE", f"{PLK}/{ana}", None, A)
check("an admin clears a link", st == 200 and r.get("removed") is True, (st, r))
st, r = http("DELETE", f"{PLK}/{ana}", None, A)
check("clearing it again is not an error", st == 200 and r.get("removed") is False, (st, r))
st, r = http("DELETE", f"{PLK}/{ana}", None, M)
check("a member cannot clear a link", st in (400, 403), (st, r))

st, f = http("POST", PL + "/person-link-fill", {}, M)
check("a member cannot run the fill", st in (400, 403) and "E-USR-001" in msg(f), (st, f))
st, f = http("POST", PL + "/person-link-fill", {}, A)
check("T-03-3 the fill REPORTS first and writes nothing by default", st == 200 and f.get("applied") is False and f.get("linked") == 0 and f.get("people_checked", 0) > 0, f)
checked = f.get("people_checked", 0)
print("   fill report (account 13):", {k: (v if not isinstance(v, list) else len(v)) for k, v in f.items()})
json.dump({"made": made, "ws": ws, "agents": {"ana": ana, "bob": bob, "bot": bot}, "tag": tag, "checked": checked}, open("req1_probe_a_state.json", "w"))
print("\nmade:", made)
print("\n%d/%d passed" % (sum(res), len(res)))
sys.exit(0 if all(res) else 1)
