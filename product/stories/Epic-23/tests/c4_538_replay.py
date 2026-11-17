"""4-C replay set for endpoint 538 (POST /workspace/{workspace_id}/timeline, start a day for one plan
person). Real HTTP as TEST admin usr2-q (account 13). Run once BEFORE the endpoint is pointed at
planner_ops/create_timeline and once AFTER; then compare:
    python c4_538_replay.py <magic_token|->  <label>      -> writes c4_538_<label>.json next to this file
    python c4_538_replay.py attach <label> <dump.json>    (one scratch dump {rows, events})
    python c4_538_replay.py compare <labelA> <labelB>    -> diffs the two (run tag, ids, times normalised)
Every run makes its own fresh plans (POST /workspace, "C4-538 <tag> ...") and plan people
(POST /workspace/{id}/agent), so before and after start from identical state. Every call except
ok_no_cid sends correlation_id "c4-538-<tag>-<case>", so its event_log rows can be found afterwards.
planner_timeline rows (table 117) and event_log rows (table 3) are read separately through the Xano
MCP (this script cannot read tables) and stored with `attach`.
Includes TWO SIMULTANEOUS requests (threads, released together) for the same person and date, twice:
the answer of each and the number of days that exist afterwards are recorded.
The switched-off-copilot rule (E-COP-059) is NOT exercised: that needs copilot user 26 switched off,
which must stay active. Covered instead: a person column and an AI column that is not linked to a login.
Never prints a token.
Fixtures: agent 48 = another account's plan person; plan 42 = another account's plan.
"""
import json, os, sys, time, threading
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from cop5_lib import req, token, PL

HERE = os.path.dirname(os.path.abspath(__file__))
OTHER_AGENT, OTHER_PLAN = 48, 42

def cases(P, A):
    m, o, a = P["main"], P["other"], P["arch"]
    pa, ai, po, parch = A["pa"], A["ai"], A["po"], A["parch"]
    return [
        # (case, workspace_id, body, send_token)
        ("ok_new_day",          m, {"agent_id": pa, "planned_date": "2026-12-02"}, True),
        ("ok_same_again",       m, {"agent_id": pa, "planned_date": "2026-12-02"}, True),
        ("ok_same_other_start", m, {"agent_id": pa, "planned_date": "2026-12-02", "start_time": "10:00"}, True),
        ("ok_start_valid",      m, {"agent_id": pa, "planned_date": "2026-12-03", "start_time": "09:30"}, True),
        ("ok_start_2359",       m, {"agent_id": pa, "planned_date": "2026-12-04", "start_time": "23:59"}, True),
        ("ok_start_0000",       m, {"agent_id": pa, "planned_date": "2026-12-05", "start_time": "00:00"}, True),
        ("ok_start_padded",     m, {"agent_id": pa, "planned_date": "2026-12-06", "start_time": "  07:15  "}, True),
        ("rej_start_2599",      m, {"agent_id": pa, "planned_date": "2026-12-07", "start_time": "25:99"}, True),
        ("rej_start_blank",     m, {"agent_id": pa, "planned_date": "2026-12-07", "start_time": ""}, True),
        ("rej_start_spaces",    m, {"agent_id": pa, "planned_date": "2026-12-07", "start_time": "   "}, True),
        ("rej_start_8_5",       m, {"agent_id": pa, "planned_date": "2026-12-07", "start_time": "8:5"}, True),
        ("case_start_null",     m, {"agent_id": pa, "planned_date": "2026-12-08", "start_time": None}, True),
        ("ok_window_first",     m, {"agent_id": pa, "planned_date": "2026-12-01"}, True),
        ("ok_window_last",      m, {"agent_id": pa, "planned_date": "2026-12-14"}, True),
        ("ok_out_before",       m, {"agent_id": pa, "planned_date": "2026-11-20"}, True),
        ("ok_out_after",        m, {"agent_id": pa, "planned_date": "2027-01-10"}, True),
        ("rej_bad_date",        m, {"agent_id": pa, "planned_date": "not-a-date"}, True),
        ("case_feb31",          m, {"agent_id": pa, "planned_date": "2026-02-31"}, True),
        ("case_date_with_time", m, {"agent_id": pa, "planned_date": "2026-12-09T15:00:00Z"}, True),
        ("rej_date_missing",    m, {"agent_id": pa}, True),
        ("rej_date_blank",      m, {"agent_id": pa, "planned_date": ""}, True),
        ("rej_status_draft",    m, {"agent_id": pa, "planned_date": "2026-12-10", "status": "draft"}, True),
        ("rej_status_blank",    m, {"agent_id": pa, "planned_date": "2026-12-10", "status": ""}, True),
        ("rej_status_null",     m, {"agent_id": pa, "planned_date": "2026-12-10", "status": None}, True),
        ("rej_status_and_time", m, {"agent_id": pa, "planned_date": "2026-12-10", "status": "published", "start_time": "99:99"}, True),
        ("ok_ai_unlinked",      m, {"agent_id": ai, "planned_date": "2026-12-02"}, True),
        ("ok_extra_ignored",    m, {"agent_id": ai, "planned_date": "2026-12-03", "id": 5, "workspace": 1, "created": False}, True),
        ("rej_agent_unknown",   m, {"agent_id": 999999, "planned_date": "2026-12-02"}, True),
        ("rej_agent_other_acct", m, {"agent_id": OTHER_AGENT, "planned_date": "2026-12-02"}, True),
        ("rej_agent_other_plan", m, {"agent_id": po, "planned_date": "2026-12-02"}, True),
        ("rej_agent_zero",      m, {"agent_id": 0, "planned_date": "2026-12-02"}, True),
        ("rej_agent_missing",   m, {"planned_date": "2026-12-02"}, True),
        ("rej_plan_unknown",    999999, {"agent_id": pa, "planned_date": "2026-12-11"}, True),
        ("rej_plan_other_acct", OTHER_PLAN, {"agent_id": pa, "planned_date": "2026-12-11"}, True),
        ("rej_plan_zero",       0, {"agent_id": pa, "planned_date": "2026-12-11"}, True),
        ("rej_archived",        a, {"agent_id": parch, "planned_date": "2026-12-02"}, True),
        ("rej_archived_badtime", a, {"agent_id": parch, "planned_date": "2026-12-02", "start_time": "99:99"}, True),  # archive wins
        ("rej_order_agent_vs_time", m, {"agent_id": po, "planned_date": "2026-12-12", "start_time": "99:99"}, True),
        ("ok_no_cid",           m, {"agent_id": pa, "planned_date": "2026-12-12"}, True),
        ("ok_cid_padded",       m, {"agent_id": pa, "planned_date": "2026-12-13"}, True),
        ("rej_no_auth",         m, {"agent_id": pa, "planned_date": "2026-12-13"}, False),
    ]

def norm(o, tag, P, A):
    s = json.dumps(o, sort_keys=True).replace(tag, "<TAG>")
    for k, v in P.items():
        s = s.replace('"workspace_id": %d' % v, '"workspace_id": "<%s>"' % k)
    for k, v in A.items():
        s = s.replace('"agent_id": %d' % v, '"agent_id": "<%s>"' % k)
    o = json.loads(s)
    if isinstance(o, dict) and isinstance(o.get("timeline"), dict):
        o["timeline"] = {k: v for k, v in o["timeline"].items() if k not in ("id", "created_at", "updated_at")}
    return o

def mkplan(T, tag, what):
    c, r = req("POST", PL + "/workspace", {"name": "C4-538 %s %s" % (tag, what),
               "planning_window_start": "2026-12-01", "planning_window_end": "2026-12-14"}, T)
    assert c == 200, "could not make test plan: %s" % str(r)[:200]
    return r["workspace"]["id"]

def mkagent(T, ws, tag, what, kind="person"):
    c, r = req("POST", PL + "/workspace/%d/agent" % ws, {"name": "C4-538 %s %s" % (tag, what), "kind": kind}, T)
    assert c == 200, "could not make test person: %s" % str(r)[:200]
    return r["agent"]["id"]

def pair(T, ws, body):
    """Two identical requests released at the same moment. Returns both answers (sorted)."""
    out = [None, None]; gate = threading.Barrier(2)
    def go(i):
        gate.wait()
        out[i] = req("POST", PL + "/workspace/%d/timeline" % ws, body, T)
    th = [threading.Thread(target=go, args=(i,)) for i in (0, 1)]
    for t in th: t.start()
    for t in th: t.join()
    return out

def run(label):
    T = token(sys.argv)
    tag = time.strftime("%H%M%S")
    P = {w: mkplan(T, tag, w) for w in ("main", "other", "arch")}
    A = {"pa": mkagent(T, P["main"], tag, "pa"), "ai": mkagent(T, P["main"], tag, "ai", "ai"),
         "pr1": mkagent(T, P["main"], tag, "pr1"), "pr2": mkagent(T, P["main"], tag, "pr2"),
         "po": mkagent(T, P["other"], tag, "po"), "parch": mkagent(T, P["arch"], tag, "parch")}
    c, r = req("POST", PL + "/workspace/%d/archive" % P["arch"], {"is_archived": True}, T)
    assert c == 200, "could not archive test plan: %s" % str(r)[:200]
    out = {"tag": tag, "label": label, "plans": P, "agents": A, "results": {}}
    for name, ws, body, auth in cases(P, A):
        b = dict(body)
        if name == "ok_cid_padded":
            b["correlation_id"] = "   c4-538-%s-%s   " % (tag, name)
        elif name != "ok_no_cid":
            b["correlation_id"] = "c4-538-%s-%s" % (tag, name)
        c, r = req("POST", PL + "/workspace/%d/timeline" % ws, b, T if auth else None)
        rn = norm(r, tag, P, A)
        if isinstance(rn, dict) and c != 200:
            rn = {k: rn.get(k) for k in ("code", "message", "payload")}
        out["results"][name] = {"http": c, "body": rn}
        print("%-26s %s  %s" % (name, c, json.dumps(rn)[:160]))
    # Two saves at the same moment, twice (fresh person each time).
    for name, who, d in (("race_1", "pr1", "2026-12-05"), ("race_2", "pr2", "2026-12-06")):
        b = {"agent_id": A[who], "planned_date": d, "correlation_id": "c4-538-%s-%s" % (tag, name)}
        res = pair(T, P["main"], b)
        ids = [r.get("timeline", {}).get("id") if isinstance(r, dict) and isinstance(r.get("timeline"), dict) else None for _, r in res]
        ans = sorted([{"http": c, "body": norm(r, tag, P, A) if c == 200 else {k: r.get(k) for k in ("code", "message")}} for c, r in res],
                     key=lambda x: json.dumps(x, sort_keys=True))
        out["results"][name] = {"answers": ans, "same_timeline_id": ids[0] is not None and ids[0] == ids[1]}
        print("%-26s %s" % (name, json.dumps(out["results"][name])[:300]))
    p = os.path.join(HERE, "c4_538_%s.json" % label)
    json.dump(out, open(p, "w"), indent=1)
    print("\ntag", tag, "plans", P, "agents", A, "-> saved", p)

def attach(label, dump_file):
    """dump_file: {rows: planner_timeline rows for the run's plans, events: event_log rows since the run}."""
    p = os.path.join(HERE, "c4_538_%s.json" % label)
    out = json.load(open(p)); tag = out["tag"]; P = out["plans"]; A = out["agents"]
    invP = {v: k for k, v in P.items()}; invA = {v: k for k, v in A.items()}
    d = json.load(open(dump_file))
    rows = [r for r in d["rows"] if r.get("workspace_id") in invP]
    rows.sort(key=lambda r: (invA.get(r["agent_id"], str(r["agent_id"])), str(r["planned_date"])))
    tl = {r["id"]: "%s@%s" % (invA.get(r["agent_id"], r["agent_id"]), r["planned_date"]) for r in rows}
    out["rows"] = [{"plan": invP[r["workspace_id"]], "agent": invA.get(r["agent_id"], r["agent_id"]),
                    "planned_date": r.get("planned_date"), "start_time": r.get("start_time"),
                    "status": r.get("status")} for r in rows]
    ev = d["events"]
    mine = [e for e in ev if (tag in (e.get("correlation_id") or "")) or
            (e.get("entity_type") == "planner_timeline" and e.get("entity_id") in tl) or
            (e.get("entity_type") == "planner_workspace" and e.get("entity_id") in invP)]
    mine.sort(key=lambda e: e["id"])
    keep = []
    for e in mine:
        eid = e.get("entity_id")
        if e.get("entity_type") == "planner_timeline": eid = tl.get(eid, eid)
        elif e.get("entity_type") == "planner_workspace": eid = invP.get(eid, eid)
        keep.append({
            "case": (e.get("correlation_id") or "").replace("c4-538-%s-" % tag, ""),
            "entity": eid, "feature": e.get("feature"), "step": e.get("step"), "outcome": e.get("outcome"),
            "severity": e.get("severity"), "error_code": e.get("error_code"), "message": e.get("message"),
            "user_id": e.get("user_id"), "account_id": e.get("account_id"), "entity_type": e.get("entity_type"),
            "metadata": json.loads(json.dumps(e.get("metadata") or {}).replace(tag, "<TAG>")),
        })
    # race events are ordered by thread timing; sort them stably by content so before/after compare.
    keep.sort(key=lambda e: (e["case"].startswith("race"), json.dumps(e, sort_keys=True) if e["case"].startswith("race") else ""))
    out["events"] = keep
    json.dump(out, open(p, "w"), indent=1)
    print("attached %d rows and %d events to %s" % (len(out["rows"]), len(keep), p))

def compare(a, b):
    A = json.load(open(os.path.join(HERE, "c4_538_%s.json" % a)))
    B = json.load(open(os.path.join(HERE, "c4_538_%s.json" % b)))
    same = total = 0
    for k in A["results"]:
        total += 1
        x = A["results"][k]; y = B["results"].get(k)
        if x == y: same += 1; print("SAME  " + k)
        else: print("DIFF  " + k + "\n   " + json.dumps(x)[:400] + "\n   " + json.dumps(y)[:400])
    total += 1
    if A.get("rows") == B.get("rows"): same += 1; print("SAME  rows written (%d)" % len(A.get("rows", [])))
    else:
        print("DIFF  rows")
        for u, v in zip(A.get("rows", []), B.get("rows", [])):
            if u != v: print("   A: %s\n   B: %s" % (u, v))
        print("   counts %d vs %d" % (len(A.get("rows", [])), len(B.get("rows", []))))
    total += 1
    ea = [json.dumps(e, sort_keys=True) for e in A.get("events", [])]
    eb = [json.dumps(e, sort_keys=True) for e in B.get("events", [])]
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
    else: run(sys.argv[2] if len(sys.argv) > 2 else "run")
