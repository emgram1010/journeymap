"""4-C replay set for endpoint 554 (POST /work_item, add a job to a plan). Real HTTP as TEST admin
usr2-q (account 13). Run once BEFORE the endpoint is pointed at planner_ops/create_work_item and once
AFTER; then compare:
    python c4_554_replay.py <magic_token|->  <label>      -> writes c4_554_<label>.json next to this file
    python c4_554_replay.py attach <label> <dump.json>    ({jobs_db, tasks_db, events: [[id, cid, feature, step,
                                                          outcome, error_code, entity_type, entity_id, message, metadata]...]}
                                                          transcribed from the scratch dump function run straight after)
    python c4_554_replay.py recapture <label>             (re-read the rows of a saved run over HTTP)
    python c4_554_replay.py compare <labelA> <labelB>    -> diffs the two (run tag, ids, times normalised)
Rows are captured IN THE SAME RUN over HTTP: after the cases, every plan's job list (GET
/workspace/{id}/work_item?include_cancelled=true) and every created job (GET /work_item/{id}) are read
and stored, so a refusal that still wrote a job shows up as an extra row. The event_log rows (and the raw
work_item / work_task rows, as a cross-check) cannot be read over HTTP; they come from the scratch dump
function, run straight after, and are added with `attach`. The run prints the exact dump input.
Every run makes its own fresh plans ("C4-554 <tag> ...") that accept map 261 (published), so before
and after start from identical state. Map 235 is never published (so no plan can accept it: the plan
`nopub` records that refusal); map 193 is another account's; plan 42 is another account's.
Every call except ok_no_cid sends correlation_id "c4-554-<tag>-<case>". Never prints a token.
"""
import json, os, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from cop5_lib import req, token, PL

HERE = os.path.dirname(os.path.abspath(__file__))
MAP_OK, MAP_UNPUB, MAP_OTHER, OTHER_PLAN = 261, 235, 193, 42
T120 = "J" * 120

def cases(P, J):
    """J holds job ids made by earlier cases (parents). Evaluated lazily: each case is (name, fn)."""
    m, o, a, n = P["main"], P["other"], P["arch"], P["nopub"]
    return [
        ("ok_basic",            lambda: {"workspace_id": m, "journey_map_id": MAP_OK, "title": "Job basic"}),
        ("ok_attrs",            lambda: {"workspace_id": m, "journey_map_id": MAP_OK, "title": "Job attrs", "attributes": {"colour": "red", "n": 2}}),
        ("ok_attrs_null",       lambda: {"workspace_id": m, "journey_map_id": MAP_OK, "title": "Job attrs null", "attributes": None}),
        ("ok_attrs_empty",      lambda: {"workspace_id": m, "journey_map_id": MAP_OK, "title": "Job attrs empty", "attributes": {}}),
        ("ok_attrs_list",       lambda: {"workspace_id": m, "journey_map_id": MAP_OK, "title": "Job attrs list", "attributes": [1, 2]}),
        ("ok_title_padded",     lambda: {"workspace_id": m, "journey_map_id": MAP_OK, "title": "   Padded job   "}),
        ("ok_title_120",        lambda: {"workspace_id": m, "journey_map_id": MAP_OK, "title": T120}),
        ("ok_title_lt",         lambda: {"workspace_id": m, "journey_map_id": MAP_OK, "title": "a < b and 3>2"}),
        ("ok_title_unicode",    lambda: {"workspace_id": m, "journey_map_id": MAP_OK, "title": "Order · Repair — x"}),
        ("ok_extra_ignored",    lambda: {"workspace_id": m, "journey_map_id": MAP_OK, "title": "Job extra", "status": "done", "account_id": 1, "created_by": 1}),
        ("ok_parent_zero",      lambda: {"workspace_id": m, "journey_map_id": MAP_OK, "title": "Job parent 0", "parent_work_item_id": 0}),
        ("ok_other_plan_job",   lambda: {"workspace_id": o, "journey_map_id": MAP_OK, "title": "Job in other plan"}),
        ("ok_to_cancel",        lambda: {"workspace_id": m, "journey_map_id": MAP_OK, "title": "Job to cancel"}),
        ("CANCEL",              None),
        ("ok_child",            lambda: {"workspace_id": m, "journey_map_id": MAP_OK, "title": "Job child", "parent_work_item_id": J["ok_basic"]}),
        ("ok_child_attrs",      lambda: {"workspace_id": m, "journey_map_id": MAP_OK, "title": "Job child attrs", "parent_work_item_id": J["ok_basic"], "attributes": {"k": "v"}}),
        ("rej_parent_unknown",  lambda: {"workspace_id": m, "journey_map_id": MAP_OK, "title": "Job p unknown", "parent_work_item_id": 999999}),
        ("rej_parent_other_plan", lambda: {"workspace_id": m, "journey_map_id": MAP_OK, "title": "Job p other", "parent_work_item_id": J["ok_other_plan_job"]}),
        ("rej_parent_other_acct", lambda: {"workspace_id": m, "journey_map_id": MAP_OK, "title": "Job p acct", "parent_work_item_id": 1}),
        ("rej_parent_cancelled", lambda: {"workspace_id": m, "journey_map_id": MAP_OK, "title": "Job p cancelled", "parent_work_item_id": J["ok_to_cancel"]}),
        ("rej_parent_negative", lambda: {"workspace_id": m, "journey_map_id": MAP_OK, "title": "Job p neg", "parent_work_item_id": -5}),
        ("rej_title_and_parent", lambda: {"workspace_id": m, "journey_map_id": MAP_OK, "title": "", "parent_work_item_id": 999999}),
        ("rej_map_and_parent",  lambda: {"workspace_id": m, "journey_map_id": MAP_UNPUB, "title": "Job m+p", "parent_work_item_id": 999999}),
        ("rej_title_blank",     lambda: {"workspace_id": m, "journey_map_id": MAP_OK, "title": ""}),
        ("rej_title_spaces",    lambda: {"workspace_id": m, "journey_map_id": MAP_OK, "title": "     "}),
        ("rej_title_missing",   lambda: {"workspace_id": m, "journey_map_id": MAP_OK}),
        ("rej_title_null",      lambda: {"workspace_id": m, "journey_map_id": MAP_OK, "title": None}),
        ("rej_title_121",       lambda: {"workspace_id": m, "journey_map_id": MAP_OK, "title": T120 + "X"}),
        ("rej_title_html",      lambda: {"workspace_id": m, "journey_map_id": MAP_OK, "title": "<b>bold</b> job"}),
        ("rej_title_script",    lambda: {"workspace_id": m, "journey_map_id": MAP_OK, "title": "x<script>alert(1)</script>"}),
        ("rej_title_number",    lambda: {"workspace_id": m, "journey_map_id": MAP_OK, "title": 12345}),
        ("rej_map_unpublished", lambda: {"workspace_id": m, "journey_map_id": MAP_UNPUB, "title": "Job unpublished map"}),
        ("rej_map_nopub_plan",  lambda: {"workspace_id": n, "journey_map_id": MAP_UNPUB, "title": "Job nopub plan"}),
        ("rej_map_not_accepted_ok_map", lambda: {"workspace_id": n, "journey_map_id": MAP_OK, "title": "Job map not accepted"}),
        ("rej_map_unknown",     lambda: {"workspace_id": m, "journey_map_id": 999999, "title": "Job unknown map"}),
        ("rej_map_other_acct",  lambda: {"workspace_id": m, "journey_map_id": MAP_OTHER, "title": "Job other map"}),
        ("rej_map_zero",        lambda: {"workspace_id": m, "journey_map_id": 0, "title": "Job map 0"}),
        ("rej_map_missing",     lambda: {"workspace_id": m, "title": "Job no map"}),
        ("rej_title_and_map",   lambda: {"workspace_id": m, "journey_map_id": 999999, "title": "<i>x</i>"}),
        ("rej_plan_unknown",    lambda: {"workspace_id": 999999, "journey_map_id": MAP_OK, "title": "Job unknown plan"}),
        ("rej_plan_other_acct", lambda: {"workspace_id": OTHER_PLAN, "journey_map_id": MAP_OK, "title": "Job other plan"}),
        ("rej_plan_zero",       lambda: {"workspace_id": 0, "journey_map_id": MAP_OK, "title": "Job plan 0"}),
        ("rej_plan_missing",    lambda: {"journey_map_id": MAP_OK, "title": "Job no plan"}),
        ("rej_plan_text",       lambda: {"workspace_id": "abc", "journey_map_id": MAP_OK, "title": "Job plan text"}),
        ("rej_archived",        lambda: {"workspace_id": a, "journey_map_id": MAP_OK, "title": "Job archived"}),
        ("rej_archived_badtitle", lambda: {"workspace_id": a, "journey_map_id": MAP_OK, "title": ""}),
        ("ok_no_cid",           lambda: {"workspace_id": m, "journey_map_id": MAP_OK, "title": "Job no cid"}),
        ("ok_cid_padded",       lambda: {"workspace_id": m, "journey_map_id": MAP_OK, "title": "Job cid padded"}),
        ("rej_no_auth",         lambda: {"workspace_id": m, "journey_map_id": MAP_OK, "title": "Job no auth"}),
    ]

def mkplan(T, tag, what):
    c, r = req("POST", PL + "/workspace", {"name": "C4-554 %s %s" % (tag, what),
               "planning_window_start": "2026-12-01", "planning_window_end": "2026-12-14"}, T)
    assert c == 200, "could not make test plan: %s" % str(r)[:200]
    return r["workspace"]["id"]

class Norm:
    def __init__(self, tag, P):
        self.tag, self.P, self.jobs = tag, P, {}   # jobs: id -> case name
    def s(self, o):
        s = json.dumps(o, sort_keys=True).replace(self.tag, "<TAG>")
        for k, v in self.P.items():
            s = s.replace('"workspace_id": %d' % v, '"workspace_id": "<%s>"' % k)
        for jid, name in self.jobs.items():
            for key in ("parent_work_item_id", "entity_id", "work_item_id"):
                s = s.replace('"%s": %d,' % (key, jid), '"%s": "<job:%s>",' % (key, name))
                s = s.replace('"%s": %d}' % (key, jid), '"%s": "<job:%s>"}' % (key, name))
        return json.loads(s)
    def job(self, w):
        w = self.s(w)
        w = {k: v for k, v in w.items() if k not in ("id", "created_at", "updated_at")}
        if w.get("finished_at"): w["finished_at"] = "<set>"   # the cancel fixture's own timestamp
        return w

def run(label):
    T = token(sys.argv)
    tag = time.strftime("%H%M%S")
    since = int(time.time() * 1000) - 5000
    P = {w: mkplan(T, tag, w) for w in ("main", "other", "arch", "nopub")}
    fixtures = {}
    for w in ("main", "other", "arch"):
        c, r = req("POST", PL + "/workspace/%d/map" % P[w], {"map_ids": [MAP_OK]}, T)
        assert c == 200, "could not accept map 261: %s" % str(r)[:200]
    c, r = req("POST", PL + "/workspace/%d/map" % P["nopub"], {"map_ids": [MAP_UNPUB]}, T)
    fixtures["accept_unpublished_235"] = {"http": c, "body": {k: r.get(k) for k in ("code", "message")} if c != 200 else "accepted"}
    c, r = req("POST", PL + "/workspace/%d/archive" % P["arch"], {"is_archived": True}, T)
    assert c == 200, "could not archive test plan: %s" % str(r)[:200]
    N = Norm(tag, P); J = {}
    out = {"tag": tag, "label": label, "since_ms": since, "plans": P, "fixtures": fixtures, "results": {}}
    for name, fn in cases(P, J):
        if name == "CANCEL":
            c, r = req("POST", PL + "/work_item/%d/cancel" % J["ok_to_cancel"], {"correlation_id": "c4-554-%s-cancel" % tag}, T)
            assert c == 200, "could not cancel: %s" % str(r)[:200]
            continue
        b = fn()
        if name == "ok_cid_padded":
            b["correlation_id"] = "   c4-554-%s-%s   " % (tag, name)
        elif name != "ok_no_cid":
            b["correlation_id"] = "c4-554-%s-%s" % (tag, name)
        c, r = req("POST", PL + "/work_item", b, None if name == "rej_no_auth" else T)
        if c == 200 and isinstance(r, dict) and isinstance(r.get("work_item"), dict):
            J[name] = r["work_item"]["id"]; N.jobs[r["work_item"]["id"]] = name
            rn = N.s(r); rn["work_item"] = N.job(r["work_item"])
        else:
            rn = N.s(r)
            if isinstance(rn, dict) and c != 200:
                rn = {k: rn.get(k) for k in ("code", "message", "payload")}
        out["results"][name] = {"http": c, "body": rn}
        print("%-30s %s  %s" % (name, c, json.dumps(rn)[:150]))
    capture_rows(T, out, N, P, J)
    p = os.path.join(HERE, "c4_554_%s.json" % label)
    json.dump(out, open(p, "w"), indent=1)
    print("\ntag", tag, "plans", P, "-> saved", p)
    print("DUMP INPUT:", json.dumps({"since_ms": since, "workspace_ids": list(P.values())}))

def recapture(label):
    """Re-read the rows of a saved run (only if the row reader itself was fixed; the cases are not re-sent)."""
    T = token(["x", "-"]); p = os.path.join(HERE, "c4_554_%s.json" % label)
    out = json.load(open(p)); N = Norm(out["tag"], out["plans"]); J = out["job_ids"]
    N.jobs = {v: k for k, v in J.items()}
    capture_rows(T, out, N, out["plans"], J)
    json.dump(out, open(p, "w"), indent=1); print("rows re-read for", p)

def capture_rows(T, out, N, P, J):
    # Rows, same run, over HTTP: every plan's job list, then each created job with its tasks.
    rows = {}
    for w, pid in P.items():
        c, r = req("GET", PL + "/workspace/%d/work_item?include_cancelled=true" % pid, None, T)
        items = r.get("work_items", []) if c == 200 and isinstance(r, dict) else r
        rows[w] = {"http": c, "jobs": sorted([[(i.get("work_item") or {}).get("title"), (i.get("work_item") or {}).get("status"),
                                               i.get("task_count"), i.get("child_count")] for i in items], key=str) if isinstance(items, list) else items}
    detail = {}
    for name, jid in J.items():
        c, r = req("GET", PL + "/work_item/%d" % jid, None, T)
        if c == 200:
            detail[name] = {"work_item": N.job(r["work_item"]),
                            "tasks": [{k: v for k, v in t.items() if k not in ("id", "created_at", "updated_at", "work_task_id", "work_item_id")} for t in N.s(r.get("tasks") or [])],
                            "pinned_version": r.get("pinned_version"),
                            "parent": {k: v for k, v in N.s(r.get("parent")).items() if k != "created_at"} if isinstance(r.get("parent"), dict) else r.get("parent"),
                            "children": sorted([N.s(x).get("title", "") if isinstance(x, dict) else x for x in (r.get("children") or [])], key=str)}
        else:
            detail[name] = {"http": c, "body": r}
    out["rows_http"] = {"plans": rows, "jobs": detail}
    out["job_ids"] = J

def attach(label, dump_file):
    p = os.path.join(HERE, "c4_554_%s.json" % label)
    out = json.load(open(p)); tag = out["tag"]; P = out["plans"]
    N = Norm(tag, P); N.jobs = {v: k for k, v in out["job_ids"].items()}
    invP = {v: k for k, v in P.items()}
    d = json.load(open(dump_file))
    d = d.get("result", d)
    jname = dict(N.jobs)
    out["rows_db"] = {"work_item": d["jobs_db"], "work_task": d["tasks_db"]}
    # Compact rows transcribed from the dump: [id, cid, feature, step, outcome, error_code, entity_type, entity_id, message, metadata]
    cols = ("id", "correlation_id", "feature", "step", "outcome", "error_code", "entity_type", "entity_id", "message", "metadata")
    d["events"] = [dict(zip(cols, e)) if isinstance(e, list) else e for e in d["events"]]
    mine = [e for e in d["events"] if tag in (e.get("correlation_id") or "") or
            (e.get("entity_type") == "work_item" and e.get("entity_id") in jname) or
            (e.get("entity_type") == "planner_workspace" and e.get("entity_id") in invP)]
    mine.sort(key=lambda e: e["id"])
    keep = []
    for e in mine:
        eid = e.get("entity_id")
        if e.get("entity_type") == "work_item": eid = jname.get(eid, eid)
        elif e.get("entity_type") == "planner_workspace": eid = invP.get(eid, eid)
        keep.append({"case": (e.get("correlation_id") or "").strip().replace("c4-554-%s-" % tag, ""),
                     "cid_raw_padded": (e.get("correlation_id") or "") != (e.get("correlation_id") or "").strip(),
                     "entity": eid, "feature": e.get("feature"), "step": e.get("step"), "outcome": e.get("outcome"),
                     "severity": e.get("severity"), "error_code": e.get("error_code"), "message": e.get("message"),
                     "user_id": e.get("user_id"), "account_id": e.get("account_id"), "entity_type": e.get("entity_type"),
                     "action": e.get("action"), "metadata": N.s(e.get("metadata") or {})})
    out["events"] = keep
    out["versions"] = {"unpublished": d.get("unpublished_versions"), "all": d.get("all_versions")}
    json.dump(out, open(p, "w"), indent=1)
    print("attached %d jobs, %d tasks, %d events to %s" % (d["jobs_db"], d["tasks_db"], len(keep), p))

def compare(a, b):
    A = json.load(open(os.path.join(HERE, "c4_554_%s.json" % a)))
    B = json.load(open(os.path.join(HERE, "c4_554_%s.json" % b)))
    same = total = 0
    def chk(name, x, y):
        nonlocal same, total
        total += 1
        if x == y: same += 1; print("SAME  " + name)
        else: print("DIFF  " + name + "\n   A: " + json.dumps(x)[:600] + "\n   B: " + json.dumps(y)[:600])
    chk("fixture accept 235", A["fixtures"], B["fixtures"])
    for k in A["results"]: chk(k, A["results"][k], B["results"].get(k))
    chk("rows over HTTP: plan job lists", A["rows_http"]["plans"], B["rows_http"]["plans"])
    chk("rows over HTTP: each job + tasks", A["rows_http"]["jobs"], B["rows_http"]["jobs"])
    chk("row counts in db (work_item, work_task)", A.get("rows_db"), B.get("rows_db"))
    chk("versions without published_at", A.get("versions"), B.get("versions"))
    ea = [json.dumps(e, sort_keys=True) for e in A.get("events", [])]
    eb = [json.dumps(e, sort_keys=True) for e in B.get("events", [])]
    total += 1
    if ea == eb: same += 1; print("SAME  events (%d)" % len(ea))
    else:
        print("DIFF  events (%d vs %d)" % (len(ea), len(eb)))
        for i in range(max(len(ea), len(eb))):
            u = ea[i] if i < len(ea) else None; v = eb[i] if i < len(eb) else None
            if u != v: print("   A: %s\n   B: %s" % (u, v))
    print("\n%d/%d matching" % (same, total))
    sys.exit(0 if same == total else 1)

if __name__ == "__main__":
    if sys.argv[1] == "compare": compare(sys.argv[2], sys.argv[3])
    elif sys.argv[1] == "attach": attach(sys.argv[2], sys.argv[3])
    elif sys.argv[1] == "recapture": recapture(sys.argv[2])
    else: run(sys.argv[2] if len(sys.argv) > 2 else "run")
