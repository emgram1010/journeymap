"""4-C replay set for endpoint 560 (POST /work_task/{work_task_id}/schedule, put one job step onto a day).
Real HTTP as TEST admin usr2-q (account 13). Run once BEFORE the endpoint is pointed at
planner_ops/schedule_work_task and once AFTER; then compare:
    python c4_560_replay.py setup <magic_token|-> <label>   -> fresh plans, people, days, jobs (c4_560_<label>.json)
        (then run scratch/c4_560_fixture_patch {"work_item_id": <mv job>} - points ONE fresh test job at a
         version id that does not exist, the "pinned version missing" case; the job sits alone in plan "mv")
    python c4_560_replay.py cases <label>                   -> runs every case, prints the dump input
    python c4_560_replay.py attach <label> <dump.json>      (scratch/c4_560_dump result: slots, links, events)
    python c4_560_replay.py compare <labelA> <labelB>       -> diffs the two (run tag, ids, times normalised)
Every run makes its own plans ("C4-560 <tag> ..."): main (two people, two draft days, jobs on map 261),
other (another plan of the same account), arch (archived after its job and day are made), mv (the
missing-version job). The LIVE day is day 53 in plan 44 (already published, account 13): each run adds one
fresh job to plan 44 and schedules its first step there - nothing new is published. The switched-off-
copilot rule (E-COP-059) is NOT exercised: copilot user 26 must stay active.
Fixtures from other accounts: work_task 753, timeline 40, agent 48 (account 2).
Includes TWO IDENTICAL REQUESTS AT THE SAME MOMENT (threads released together), twice; the answers and
the slots/links that exist afterwards are recorded. Every call except ok_no_cid sends correlation_id
"c4-560-<tag>-<case>". Never prints a token.
"""
import json, os, sys, time, threading
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from cop5_lib import req, token, PL

HERE = os.path.dirname(os.path.abspath(__file__))
MAP_OK, LIVE_PLAN, LIVE_DAY = 261, 44, 53
OTHER_STEP, OTHER_DAY, OTHER_AGENT = 753, 40, 48

def path(label): return os.path.join(HERE, "c4_560_%s.json" % label)

def ok(c, r, what):
    assert c == 200, "%s failed: %s %s" % (what, c, str(r)[:300])
    return r

def mkjob(T, tag, ws, what):
    r = ok(*req("POST", PL + "/work_item", {"workspace_id": ws, "journey_map_id": MAP_OK, "title": "C4-560 %s %s" % (tag, what)}, T), "job " + what)
    jid = r["work_item"]["id"]
    d = ok(*req("GET", PL + "/work_item/%d" % jid, None, T), "read job " + what)
    steps = {t["stage_key"]: t["id"] for t in d["tasks"]}
    return {"id": jid, "s1": steps["s1"], "s2": steps["s2"]}

def setup(label):
    T = token(sys.argv[1:])
    tag = time.strftime("%H%M%S")
    since = int(time.time() * 1000) - 5000
    P, A, D, J = {}, {}, {}, {}
    for w in ("main", "other", "arch", "mv"):
        r = ok(*req("POST", PL + "/workspace", {"name": "C4-560 %s %s" % (tag, w), "planning_window_start": "2026-12-01",
                                                  "planning_window_end": "2026-12-14"}, T), "plan " + w)
        P[w] = r["workspace"]["id"]
        ok(*req("POST", PL + "/workspace/%d/map" % P[w], {"map_ids": [MAP_OK]}, T), "accept 261 in " + w)
    for name, w in (("pa", "main"), ("pb", "main"), ("po", "other"), ("parch", "arch"), ("pmv", "mv")):
        r = ok(*req("POST", PL + "/workspace/%d/agent" % P[w], {"name": "C4-560 %s %s" % (tag, name), "kind": "person"}, T), "agent " + name)
        A[name] = r["agent"]["id"]
    for name, w, who, d in (("D", "main", "pa", "2026-12-02"), ("D2", "main", "pa", "2026-12-03"), ("DO", "other", "po", "2026-12-02"),
                            ("DA", "arch", "parch", "2026-12-02"), ("DMV", "mv", "pmv", "2026-12-02")):
        r = ok(*req("POST", PL + "/workspace/%d/timeline" % P[w], {"agent_id": A[who], "planned_date": d}, T), "day " + name)
        D[name] = r["timeline"]["id"]
    for j in ("J1", "J2", "J3", "J4", "J5", "J6", "J7", "JC"):
        J[j] = mkjob(T, tag, P["main"], j)
    J["JO"] = mkjob(T, tag, P["other"], "JO")
    J["JA"] = mkjob(T, tag, P["arch"], "JA")
    J["JMV"] = mkjob(T, tag, P["mv"], "JMV")
    J["J44"] = mkjob(T, tag, LIVE_PLAN, "J44")
    ok(*req("POST", PL + "/work_item/%d/cancel" % J["JC"]["id"], {"correlation_id": "c4-560-%s-fixture-cancel" % tag}, T), "cancel JC")
    ok(*req("POST", PL + "/workspace/%d/archive" % P["arch"], {"is_archived": True}, T), "archive")
    out = {"tag": tag, "label": label, "since_ms": since, "plans": P, "agents": A, "days": D, "jobs": J, "results": {}}
    json.dump(out, open(path(label), "w"), indent=1)
    print("tag", tag, "-> saved", path(label))
    print("PATCH INPUT:", json.dumps({"work_item_id": J["JMV"]["id"]}))

def cases(P, A, D, J):
    s = lambda j, k: J[j][k]
    return [
        # (case, work_task_id, body, send_token)
        ("ok_default",            s("J1", "s1"), {"timeline_id": D["D"]}, True),
        ("ok_duration_45",        s("J1", "s2"), {"timeline_id": D["D"], "duration_minutes": 45}, True),
        ("ok_duration_1",         s("J2", "s1"), {"timeline_id": D["D"], "duration_minutes": 1}, True),
        ("ok_duration_1440",      s("J2", "s2"), {"timeline_id": D["D"], "duration_minutes": 1440}, True),
        ("ok_duration_30_same",   s("J5", "s1"), {"timeline_id": D["D"], "duration_minutes": 30}, True),
        ("rej_duration_0",        s("J3", "s1"), {"timeline_id": D["D"], "duration_minutes": 0}, True),
        ("rej_duration_1441",     s("J3", "s1"), {"timeline_id": D["D"], "duration_minutes": 1441}, True),
        ("rej_duration_neg",      s("J3", "s1"), {"timeline_id": D["D"], "duration_minutes": -5}, True),
        ("case_duration_null",    s("J3", "s1"), {"timeline_id": D["D"], "duration_minutes": None}, True),
        ("case_duration_text",    s("J3", "s1"), {"timeline_id": D["D"], "duration_minutes": "abc"}, True),
        ("case_duration_decimal", s("J3", "s1"), {"timeline_id": D["D"], "duration_minutes": 30.5}, True),
        ("case_duration_numstr",  s("J3", "s2"), {"timeline_id": D["D"], "duration_minutes": "60"}, True),
        ("rej_already",           s("J1", "s1"), {"timeline_id": D["D"]}, True),
        ("rej_already_bad_dur",   s("J1", "s1"), {"timeline_id": D["D"], "duration_minutes": 0}, True),
        ("rej_already_other_day", s("J1", "s1"), {"timeline_id": D["D2"]}, True),
        ("ok_assignee",           s("J4", "s1"), {"timeline_id": D["D"], "assignee_agent_id": A["pb"]}, True),
        ("rej_assignee_other_plan", s("J4", "s2"), {"timeline_id": D["D"], "assignee_agent_id": A["po"]}, True),
        ("rej_assignee_other_acct", s("J4", "s2"), {"timeline_id": D["D"], "assignee_agent_id": OTHER_AGENT}, True),
        ("rej_assignee_unknown",  s("J4", "s2"), {"timeline_id": D["D"], "assignee_agent_id": 999999}, True),
        ("rej_day_unknown",       s("J4", "s2"), {"timeline_id": 999999}, True),
        ("rej_day_zero",          s("J4", "s2"), {"timeline_id": 0}, True),
        ("rej_day_missing",       s("J4", "s2"), {}, True),
        ("rej_day_other_acct",    s("J4", "s2"), {"timeline_id": OTHER_DAY}, True),
        ("rej_step_other_acct",   OTHER_STEP,    {"timeline_id": D["D"]}, True),
        ("rej_step_unknown",      999999,        {"timeline_id": D["D"]}, True),
        ("rej_step_zero",         0,             {"timeline_id": D["D"]}, True),
        ("rej_cross_plan",        s("J4", "s2"), {"timeline_id": D["DO"]}, True),
        ("rej_cross_plan_rev",    s("JO", "s1"), {"timeline_id": D["D"]}, True),
        ("rej_archived",          s("JA", "s1"), {"timeline_id": D["DA"]}, True),
        ("rej_archived_main_day", s("JA", "s1"), {"timeline_id": D["D"]}, True),
        ("rej_cancelled",         s("JC", "s1"), {"timeline_id": D["D"]}, True),
        ("rej_cancelled_bad_dur", s("JC", "s1"), {"timeline_id": D["D"], "duration_minutes": 0}, True),
        ("case_missing_version",  s("JMV", "s1"), {"timeline_id": D["DMV"]}, True),
        ("ok_live_day",           s("J44", "s1"), {"timeline_id": LIVE_DAY}, True),
        ("ok_second_day",         s("J5", "s2"), {"timeline_id": D["D2"]}, True),
        ("ok_no_cid",             s("J6", "s1"), {"timeline_id": D["D2"]}, True),
        ("ok_cid_padded",         s("J3", "s1"), {"timeline_id": D["D2"]}, True),
        ("rej_no_auth",           s("J6", "s2"), {"timeline_id": D["D2"]}, False),
        ("ok_extra_ignored",      s("J6", "s2"), {"timeline_id": D["D2"], "status": "done", "title": "x", "seq": 99, "workspace_id": 1}, True),
    ]

class Norm:
    """Turns run-specific ids into names: plans, people, days, jobs, steps, slots."""
    def __init__(self, out):
        self.tag = out["tag"]
        self.m = {"workspace_id": {v: k for k, v in out["plans"].items()},
                  "agent_id": {v: k for k, v in out["agents"].items()},
                  "timeline_id": {v: k for k, v in out["days"].items()},
                  "work_item_id": {v["id"]: k for k, v in out["jobs"].items()},
                  "work_task_id": {}, "planner_task_id": dict((int(k), v) for k, v in out.get("slots", {}).items())}
        self.m["assignee_agent_id"] = self.m["agent_id"]
        for k, v in out["jobs"].items():
            self.m["work_task_id"][v["s1"]] = k + ".s1"; self.m["work_task_id"][v["s2"]] = k + ".s2"
        self.m["workspace_id"][LIVE_PLAN] = "live_plan"; self.m["timeline_id"][LIVE_DAY] = "live_day"
    def n(self, o, drop=("created_at", "updated_at")):
        if isinstance(o, dict):
            r = {}
            for k, v in o.items():
                if k in drop: continue
                if k in self.m and isinstance(v, int) and v in self.m[k]: v = "<%s>" % self.m[k][v]
                else: v = self.n(v, drop)
                r[k] = v
            return r
        if isinstance(o, list): return [self.n(x, drop) for x in o]
        if isinstance(o, str): return o.replace(self.tag, "<TAG>")
        return o

def slot_name(case): return "slot:" + case

def body_of(c, r, N, out, case):
    if c == 200 and isinstance(r, dict) and isinstance(r.get("planner_task"), dict):
        sid = r["planner_task"]["id"]
        out.setdefault("slots", {})[str(sid)] = slot_name(case); N.m["planner_task_id"][sid] = slot_name(case)
        b = N.n(r); b["planner_task"] = {k: v for k, v in b["planner_task"].items() if k != "id"}
        return b
    b = N.n(r)
    return {k: b.get(k) for k in ("code", "message", "payload")} if isinstance(b, dict) else b

def pair(T, wt, body):
    res = [None, None]; gate = threading.Barrier(2)
    def go(i):
        gate.wait(); res[i] = req("POST", PL + "/work_task/%d/schedule" % wt, body, T)
    th = [threading.Thread(target=go, args=(i,)) for i in (0, 1)]
    for t in th: t.start()
    for t in th: t.join()
    return res

def run_cases(label):
    T = token(["x", "-"])
    out = json.load(open(path(label))); tag = out["tag"]; N = Norm(out)
    P, A, D, J = out["plans"], out["agents"], out["days"], out["jobs"]
    out["results"] = {}
    for name, wt, body, auth in cases(P, A, D, J):
        b = dict(body)
        if name == "ok_cid_padded": b["correlation_id"] = "   c4-560-%s-%s   " % (tag, name)
        elif name != "ok_no_cid": b["correlation_id"] = "c4-560-%s-%s" % (tag, name)
        c, r = req("POST", PL + "/work_task/%d/schedule" % wt, b, T if auth else None)
        rn = body_of(c, r, N, out, name)
        out["results"][name] = {"http": c, "body": rn}
        print("%-26s %s  %s" % (name, c, json.dumps(rn)[:170]))
    for name, wt, extra in (("race_1", J["J7"]["s1"], {}), ("race_2", J["J7"]["s2"], {"duration_minutes": 20})):
        b = dict(timeline_id=D["D"], correlation_id="c4-560-%s-%s" % (tag, name), **extra)
        res = pair(T, wt, b)
        ans = sorted([{"http": c, "body": body_of(c, r, N, out, name)} for c, r in res], key=lambda x: json.dumps(x, sort_keys=True))
        out["results"][name] = {"answers": ans}
        print("%-26s %s" % (name, json.dumps(ans)[:400]))
    json.dump(out, open(path(label), "w"), indent=1)
    steps = [v for j in J.values() for v in (j["s1"], j["s2"])] + [OTHER_STEP]
    print("\nDUMP INPUT:", json.dumps({"since_ms": out["since_ms"], "timeline_ids": list(D.values()) + [LIVE_DAY, OTHER_DAY],
                                       "work_task_ids": steps}))

def attach(label, dump_file):
    p = path(label); out = json.load(open(p)); tag = out["tag"]; N = Norm(out)
    d = json.load(open(dump_file)); d = d.get("result", d)
    # The scratch dump answers compact rows; expand them.
    sc = ("id", "workspace_id", "timeline_id", "assignee_agent_id", "seq", "duration_minutes", "status", "title", "notes", "needs_info_reason", "tweak_reason")
    d["slots"] = [dict(zip(sc, s)) if isinstance(s, list) else s for s in d["slots"]]
    d["links"] = [dict(zip(("planner_task_id", "work_task_id", "position"), l)) if isinstance(l, list) else l for l in d["links"]]
    ec = ("correlation_id", "step", "outcome", "severity", "error_code", "entity_type", "entity_id", "message", "metadata")
    d["events"] = [dict(zip(ec, e), feature="SCHED-1", user_id=22, account_id=13) if isinstance(e, list) else e for e in d["events"]]
    assert d.get("events_not_user_22", 0) == 0, "an event was written by someone other than the test admin"
    steps = N.m["work_task_id"]; slots = {int(k): v for k, v in out.get("slots", {}).items()}
    links = [l for l in d["links"] if l["work_task_id"] in steps]
    my_slot_ids = set(slots) | {l["planner_task_id"] for l in links}
    # Slots: every slot on this run's days, plus any slot on the live day / other day that is linked to this run's steps.
    my_days = set(out["days"].values())
    rows = [s for s in d["slots"] if s["timeline_id"] in my_days or s["id"] in my_slot_ids]
    for s in rows:
        if s["id"] not in slots: slots[s["id"]] = "slot:unnamed#%d" % len(slots)
    N.m["planner_task_id"] = slots
    out["rows"] = {
        "slots": sorted([N.n({k: v for k, v in s.items() if k != "id"} | {"slot": slots[s["id"]]}) for s in rows], key=lambda x: json.dumps(x, sort_keys=True)),
        "links": sorted([N.n({k: v for k, v in l.items() if k != "id"}) for l in links], key=lambda x: json.dumps(x, sort_keys=True)),
    }
    keep = []
    for e in d["events"]:
        cid = e.get("correlation_id") or ""
        et, eid = e.get("entity_type"), e.get("entity_id")
        mine = (tag in cid) or (et == "work_task" and eid in steps) or (et == "planner_task" and eid in slots)
        if not mine or "fixture" in cid: continue
        if et == "work_task": eid = steps.get(eid, eid)
        elif et == "planner_task": eid = slots.get(eid, eid)
        keep.append({"case": cid.strip().replace("c4-560-%s-" % tag, ""), "cid_padded": cid != cid.strip(),
                     "entity": eid, "feature": e.get("feature"), "step": e.get("step"), "outcome": e.get("outcome"),
                     "severity": e.get("severity"), "error_code": e.get("error_code"), "message": e.get("message"),
                     "user_id": e.get("user_id"), "account_id": e.get("account_id"), "entity_type": et,
                     "metadata": N.n(e.get("metadata") or {})})
    keep.sort(key=lambda e: json.dumps(e, sort_keys=True))
    out["events"] = keep
    json.dump(out, open(p, "w"), indent=1)
    print("attached %d slots, %d links, %d events to %s" % (len(rows), len(links), len(keep), p))

def live_seq(o):
    """The live day (53) keeps every earlier run's slot, so its seq grows by one per run: not a difference."""
    if isinstance(o, dict):
        o = {k: live_seq(v) for k, v in o.items()}
        if o.get("timeline_id") == "<live_day>" and "seq" in o: o["seq"] = "<live-day seq>"
        return o
    if isinstance(o, list): return [live_seq(x) for x in o]
    return o

def compare(a, b):
    A = live_seq(json.load(open(path(a)))); B = live_seq(json.load(open(path(b))))
    same = total = 0
    def chk(name, x, y):
        nonlocal same, total
        total += 1
        if x == y: same += 1; print("SAME  " + name)
        else: print("DIFF  " + name + "\n   A: " + json.dumps(x)[:700] + "\n   B: " + json.dumps(y)[:700])
    for k in A["results"]: chk(k, A["results"][k], B["results"].get(k))
    srt = lambda rows: sorted(rows, key=lambda x: json.dumps(x, sort_keys=True))
    chk("slots written (%d)" % len(A["rows"]["slots"]), srt(A["rows"]["slots"]), srt(B["rows"]["slots"]))
    chk("links written (%d)" % len(A["rows"]["links"]), A["rows"]["links"], B["rows"]["links"])
    ea = [json.dumps(e, sort_keys=True) for e in A.get("events", [])]
    eb = [json.dumps(e, sort_keys=True) for e in B.get("events", [])]
    total += 1
    if ea == eb: same += 1; print("SAME  events (%d)" % len(ea))
    else:
        print("DIFF  events (%d vs %d)" % (len(ea), len(eb)))
        for e in sorted(set(ea) - set(eb)): print("   only A: " + e)
        for e in sorted(set(eb) - set(ea)): print("   only B: " + e)
    print("\n%d/%d matching" % (same, total))
    sys.exit(0 if same == total else 1)

if __name__ == "__main__":
    cmd = sys.argv[1]
    if cmd == "setup": setup(sys.argv[3])
    elif cmd == "cases": run_cases(sys.argv[2])
    elif cmd == "attach": attach(sys.argv[2], sys.argv[3])
    elif cmd == "compare": compare(sys.argv[2], sys.argv[3])
