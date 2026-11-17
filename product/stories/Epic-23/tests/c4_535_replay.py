"""4-C replay set for endpoint 535 (POST /workspace/{workspace_id}/agent, add a person or AI column to a
plan). Real HTTP as TEST admin usr2-q (account 13). Run once BEFORE the endpoint is pointed at
planner_ops/create_agent and once AFTER; then compare:
    python c4_535_replay.py <magic_token|->  <label>      -> writes c4_535_<label>.json next to this file
    python c4_535_replay.py attach <label> <rows.json> <events.json>   (one scratch dump {rows, events} may be given twice)
    python c4_535_replay.py compare <labelA> <labelB>    -> diffs the two (run tag, ids, times normalised)
Every run makes its own fresh plans (POST /workspace, "C4-535 <tag> ..."), so before and after start
from identical state. Every call except ok_no_cid sends correlation_id "c4-535-<tag>-<case>", so its
event_log rows can be found afterwards. planner_agent rows (table 116) and event_log rows (table 3) are
read separately through the Xano MCP (this script cannot read tables) and stored with `attach`.
Never prints a token.
Fixtures: model 14 = account 13's (seeded by GET /settings); model 1 = account 3's; plan 42 = another
account's plan.
"""
import json, os, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from cop5_lib import req, token, PL

HERE = os.path.dirname(os.path.abspath(__file__))
MY_MODEL, OTHER_MODEL, OTHER_PLAN = 14, 1, 42

def cases(P, tag):
    n = "C4 " + tag
    m, e, a, pal = P["main"], P["edge"], P["arch"], P["pal"]
    c = [
        # (case, workspace_id, body, send_token)
        ("ok_all_fields",     m, {"name": n + " all", "kind": "ai", "color": "#123456", "daily_capacity_hours": 6.5, "model_id": MY_MODEL}, True),
        ("ok_name_only",      m, {"name": n + " only", "kind": "person"}, True),        # every optional left out
        ("ok_no_cid",         m, {"name": n + " nocid", "kind": "person"}, True),
        ("ok_color_blank",    m, {"name": n + " cblank", "kind": "person", "color": ""}, True),
        ("ok_color_spaces",   m, {"name": n + " cspace", "kind": "person", "color": "   "}, True),
        ("ok_cap_24",         m, {"name": n + " cap24", "kind": "person", "daily_capacity_hours": 24}, True),
        ("ok_cap_small",      m, {"name": n + " capsmall", "kind": "person", "daily_capacity_hours": 0.25}, True),
        ("ok_model_zero",     m, {"name": n + " mzero", "kind": "person", "model_id": 0}, True),
        ("ok_ai_no_model",    m, {"name": n + " ainomodel", "kind": "ai"}, True),
        ("ok_60_chars",       m, {"name": (n + " sixty ").ljust(60, "x"), "kind": "person"}, True),
        ("ok_html_name",      m, {"name": "<b>" + n + " html</b>", "kind": "person"}, True),  # no HTML rule today
        ("ok_extra_ignored",  m, {"name": n + " extra", "kind": "person", "user_id": 9, "is_visible": False, "is_active": False}, True),
        ("ok_cid_padded",     m, {"name": n + " cidpad", "kind": "person"}, True),
        ("rej_cap_0",         e, {"name": n + " cap0", "kind": "person", "daily_capacity_hours": 0}, True),
        ("rej_cap_neg",       e, {"name": n + " capneg", "kind": "person", "daily_capacity_hours": -1}, True),
        ("rej_cap_over",      e, {"name": n + " capover", "kind": "person", "daily_capacity_hours": 24.01}, True),
        ("rej_cap_null",      e, {"name": n + " capnull", "kind": "person", "daily_capacity_hours": None}, True),
        ("rej_cap_string",    e, {"name": n + " capstr", "kind": "person", "daily_capacity_hours": "abc"}, True),
        ("rej_dup_name",      m, {"name": n + " only", "kind": "person"}, True),
        ("rej_dup_padded",    m, {"name": "  " + n + " only  ", "kind": "person"}, True),
        ("case_dup_lower",    m, {"name": (n + " only").lower(), "kind": "person"}, True),  # record, whatever it is
        ("rej_name_blank",    e, {"name": "", "kind": "person"}, True),
        ("rej_name_spaces",   e, {"name": "    ", "kind": "person"}, True),
        ("rej_name_missing",  e, {"kind": "person"}, True),
        ("rej_name_null",     e, {"name": None, "kind": "person"}, True),
        ("rej_61_chars",      e, {"name": (n + " long ").ljust(61, "y"), "kind": "person"}, True),
        ("rej_kind_missing",  e, {"name": n + " nokind"}, True),
        ("rej_kind_bad",      e, {"name": n + " badkind", "kind": "robot"}, True),
        ("rej_kind_blank",    e, {"name": n + " blankkind", "kind": ""}, True),
        ("rej_person_model",  e, {"name": n + " pmodel", "kind": "person", "model_id": MY_MODEL}, True),
        ("rej_other_model",   e, {"name": n + " omodel", "kind": "ai", "model_id": OTHER_MODEL}, True),
        ("rej_unknown_model", e, {"name": n + " umodel", "kind": "ai", "model_id": 999999}, True),
        ("rej_model_null",    e, {"name": n + " mnull", "kind": "ai", "model_id": None}, True),
        ("rej_order_model_vs_name", e, {"name": "", "kind": "ai", "model_id": OTHER_MODEL}, True),  # model check runs first
        ("rej_order_name_vs_cap",   e, {"name": "  ", "kind": "person", "daily_capacity_hours": 0}, True),
        ("rej_order_cap_vs_model",  e, {"name": n + " ocm", "kind": "person", "daily_capacity_hours": 30, "model_id": MY_MODEL}, True),
        ("rej_order_model_vs_dup",  m, {"name": n + " only", "kind": "person", "model_id": MY_MODEL}, True),
        ("rej_unknown_plan",  999999, {"name": n + " up", "kind": "person"}, True),
        ("rej_other_acct_plan", OTHER_PLAN, {"name": n + " oap", "kind": "person"}, True),
        ("rej_plan_zero",     0, {"name": n + " pz", "kind": "person"}, True),
        ("rej_archived",      a, {"name": n + " arch", "kind": "person"}, True),
        ("rej_archived_blank", a, {"name": "", "kind": "person"}, True),               # archive check wins
        ("rej_no_auth",       e, {"name": n + " noauth", "kind": "person"}, False),
    ]
    # Palette: nine name-only people in a fresh plan -> eight distinct colours, then a wrap to the first.
    for i in range(1, 10):
        c.append(("pal_%d" % i, pal, {"name": "%s pal %d" % (n, i), "kind": "person"}, True))
    return c

def norm(o, tag, P):
    s = json.dumps(o, sort_keys=True).replace(tag, "<TAG>")
    for k, v in P.items():
        s = s.replace('"workspace_id": %d' % v, '"workspace_id": "<%s>"' % k)
    o = json.loads(s)
    if isinstance(o, dict) and isinstance(o.get("agent"), dict):
        o["agent"] = {k: v for k, v in o["agent"].items() if k not in ("id", "created_at", "updated_at")}
    return o

def mkplan(T, tag, what):
    c, r = req("POST", PL + "/workspace", {"name": "C4-535 %s %s" % (tag, what)}, T)
    assert c == 200, "could not make test plan: %s" % str(r)[:200]
    return r["workspace"]["id"]

def run(label):
    T = token(sys.argv)
    tag = time.strftime("%H%M%S")
    P = {w: mkplan(T, tag, w) for w in ("main", "edge", "arch", "pal")}
    c, r = req("POST", PL + "/workspace/%d/archive" % P["arch"], {"is_archived": True}, T)
    assert c == 200, "could not archive test plan: %s" % str(r)[:200]
    out = {"tag": tag, "label": label, "plans": P, "results": {}}
    for name, ws, body, auth in cases(P, tag):
        b = dict(body)
        if name == "ok_cid_padded":
            b["correlation_id"] = "   c4-535-%s-%s   " % (tag, name)
        elif name != "ok_no_cid":
            b["correlation_id"] = "c4-535-%s-%s" % (tag, name)
        c, r = req("POST", PL + "/workspace/%d/agent" % ws, b, T if auth else None)
        rn = norm(r, tag, P)
        if isinstance(rn, dict) and c != 200:
            rn = {k: rn.get(k) for k in ("code", "message", "payload")}
        out["results"][name] = {"http": c, "body": rn}
        print("%-26s %s  %s" % (name, c, json.dumps(rn)[:160]))
    p = os.path.join(HERE, "c4_535_%s.json" % label)
    json.dump(out, open(p, "w"), indent=1)
    print("\ntag", tag, "plans", P, "-> saved", p)

def attach(label, rows_file, events_file):
    """rows_file: raw planner_agent search items for the run's plans; events_file: raw event_log items."""
    p = os.path.join(HERE, "c4_535_%s.json" % label)
    out = json.load(open(p)); tag = out["tag"]; P = out["plans"]; inv = {v: k for k, v in P.items()}
    rows = json.load(open(rows_file)); rows = rows.get("rows", rows.get("items", rows)) if isinstance(rows, dict) else rows
    rows = [r for r in rows if r.get("workspace_id") in inv]
    rows.sort(key=lambda r: r["id"])
    agent_name = {r["id"]: r["name"].replace(tag, "<TAG>") for r in rows}
    out["rows"] = [{
        "plan": inv[r["workspace_id"]], "name": r["name"].replace(tag, "<TAG>"), "kind": r.get("kind"),
        "color": r.get("color"), "daily_capacity_hours": r.get("daily_capacity_hours"),
        "is_visible": r.get("is_visible"), "model_id": r.get("model_id"), "user_id": r.get("user_id"),
        "is_active": r.get("is_active"),
    } for r in rows]
    ev = json.load(open(events_file)); ev = ev.get("events", ev.get("items", ev)) if isinstance(ev, dict) else ev
    mine = [e for e in ev if e.get("step") == "create_agent" and (
            (tag in (e.get("correlation_id") or "")) or
            (e.get("entity_type") == "planner_agent" and e.get("entity_id") in agent_name) or
            (e.get("entity_type") == "planner_workspace" and e.get("entity_id") in inv))]
    mine.sort(key=lambda e: e["id"])
    keep = []
    for e in mine:
        eid = e.get("entity_id")
        if e.get("entity_type") == "planner_agent": eid = agent_name.get(eid, eid)
        elif e.get("entity_type") == "planner_workspace": eid = inv.get(eid, eid)
        keep.append({
            "case": (e.get("correlation_id") or "").replace("c4-535-%s-" % tag, ""),
            "entity": eid, "feature": e.get("feature"), "step": e.get("step"), "outcome": e.get("outcome"),
            "severity": e.get("severity"), "error_code": e.get("error_code"), "message": e.get("message"),
            "user_id": e.get("user_id"), "account_id": e.get("account_id"), "entity_type": e.get("entity_type"),
            "metadata": json.loads(json.dumps(e.get("metadata") or {}).replace(tag, "<TAG>")),
        })
    out["events"] = keep
    json.dump(out, open(p, "w"), indent=1)
    print("attached %d rows and %d events to %s" % (len(out["rows"]), len(keep), p))

def compare(a, b):
    A = json.load(open(os.path.join(HERE, "c4_535_%s.json" % a)))
    B = json.load(open(os.path.join(HERE, "c4_535_%s.json" % b)))
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
    elif sys.argv[1] == "attach": attach(sys.argv[2], sys.argv[3], sys.argv[4])
    else: run(sys.argv[2] if len(sys.argv) > 2 else "run")
