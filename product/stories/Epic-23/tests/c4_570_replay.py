"""4-C replay set for endpoint 570 (POST /workspace/{workspace_id}/map, a plan accepts maps). Real HTTP
as TEST admin usr2-q (account 13). Run once BEFORE the endpoint is pointed at planner_ops/accept_maps
and once AFTER; then compare:
    python c4_570_replay.py <magic_token|->  <label>      -> writes c4_570_<label>.json next to this file
    python c4_570_replay.py compare <labelA> <labelB>    -> diffs the two (run tag and plan ids normalised)
Every run makes its own fresh plans (POST /workspace, "C4-570 <tag> ..."), so before and after start
from identical state. Every call except ok_no_cid sends correlation_id "c4-570-<tag>-<case>", so its
event_log rows can be found afterwards. planner_workspace_map rows and event_log rows are read
separately through the Xano MCP (this script cannot read tables) and stored with --rows/--events:
    python c4_570_replay.py attach <label> <rows.json> <events.json>
Never prints a token.
Fixtures in account 13: map 261 = published, map 235 = never published; map 193 = another account's
published map; plan 42 = another account's plan.
"""
import json, os, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from cop5_lib import req, token, PL

HERE = os.path.dirname(os.path.abspath(__file__))
PUB, UNPUB, OTHER_MAP, OTHER_PLAN = 261, 235, 193, 42

def cases(P):
    # (case, workspace_id, body, send_token)
    return [
        ("ok_single",          P["main"],  {"map_ids": [PUB]}, True),
        ("ok_again_idem",      P["main"],  {"map_ids": [PUB]}, True),
        ("ok_no_cid",          P["main"],  {"map_ids": [PUB]}, True),
        ("ok_string_id_idem",  P["main"],  {"map_ids": [str(PUB)]}, True),
        ("ok_cid_padded",      P["main"],  {"map_ids": [PUB]}, True),
        ("dup_in_one_call",    P["dup"],   {"map_ids": [PUB, PUB]}, True),     # the known bug
        ("rej_unpublished",    P["empty"], {"map_ids": [UNPUB]}, True),
        ("rej_mixed",          P["empty"], {"map_ids": [PUB, UNPUB]}, True),   # nothing may be written
        ("rej_other_acct_map", P["empty"], {"map_ids": [OTHER_MAP]}, True),
        ("rej_unknown_map",    P["empty"], {"map_ids": [999999]}, True),
        ("rej_zero_map",       P["empty"], {"map_ids": [0]}, True),
        ("rej_empty_list",     P["empty"], {"map_ids": []}, True),
        ("rej_missing_list",   P["empty"], {}, True),
        ("rej_null_list",      P["empty"], {"map_ids": None}, True),
        ("rej_number_not_list", P["empty"], {"map_ids": PUB}, True),
        ("rej_string_not_list", P["empty"], {"map_ids": "261"}, True),
        ("rej_unknown_plan",   999999,     {"map_ids": [PUB]}, True),
        ("rej_unknown_plan_empty", 999999, {"map_ids": []}, True),            # plan check wins
        ("rej_other_acct_plan", OTHER_PLAN, {"map_ids": [PUB]}, True),
        ("rej_archived",       P["arch"],  {"map_ids": [PUB]}, True),
        ("rej_archived_empty", P["arch"],  {"map_ids": []}, True),            # archive check wins
        ("rej_archived_unpub", P["arch"],  {"map_ids": [UNPUB]}, True),
        ("rej_no_auth",        P["empty"], {"map_ids": [PUB]}, False),
        ("rej_plan_zero",      0,          {"map_ids": [PUB]}, True),
    ]

def norm(o, tag, P):
    s = json.dumps(o, sort_keys=True).replace(tag, "<TAG>")
    for k, v in P.items():
        s = s.replace('"workspace_id": %d' % v, '"workspace_id": "<%s>"' % k)
    return json.loads(s)

def mkplan(T, tag, what):
    c, r = req("POST", PL + "/workspace", {"name": "C4-570 %s %s" % (tag, what)}, T)
    assert c == 200, "could not make test plan: %s" % str(r)[:200]
    return r["workspace"]["id"]

def run(label):
    T = token(sys.argv)
    tag = time.strftime("%H%M%S")
    P = {w: mkplan(T, tag, w) for w in ("main", "dup", "empty", "arch")}
    c, r = req("POST", PL + "/workspace/%d/archive" % P["arch"], {"is_archived": True}, T)
    assert c == 200, "could not archive test plan: %s" % str(r)[:200]
    out = {"tag": tag, "label": label, "plans": P, "results": {}}
    for name, ws, body, auth in cases(P):
        b = dict(body)
        if name == "ok_cid_padded":
            b["correlation_id"] = "   c4-570-%s-%s   " % (tag, name)
        elif name != "ok_no_cid":
            b["correlation_id"] = "c4-570-%s-%s" % (tag, name)
        c, r = req("POST", PL + "/workspace/%d/map" % ws, b, T if auth else None)
        rn = norm(r, tag, P)
        if isinstance(rn, dict) and c != 200:
            rn = {k: rn.get(k) for k in ("code", "message", "payload")}
        out["results"][name] = {"http": c, "body": rn}
        print("%-24s %s  %s" % (name, c, json.dumps(rn)[:170]))
    p = os.path.join(HERE, "c4_570_%s.json" % label)
    json.dump(out, open(p, "w"), indent=1)
    print("\ntag", tag, "plans", P, "-> saved", p)

def attach(label, rows_file, events_file):
    """rows_file: {"<plan key>": [journey_map_id, ...]}; events_file: raw event_log search items."""
    p = os.path.join(HERE, "c4_570_%s.json" % label)
    out = json.load(open(p)); tag = out["tag"]; P = out["plans"]; inv = {v: k for k, v in P.items()}
    out["rows"] = {k: sorted(v) for k, v in json.load(open(rows_file)).items()}
    ev = json.load(open(events_file))
    ev = ev.get("items", ev) if isinstance(ev, dict) else ev
    mine = [e for e in ev if (e.get("entity_id") in inv) or (tag in (e.get("correlation_id") or ""))]
    mine.sort(key=lambda e: e["id"])
    keep = []
    for e in mine:
        md = e.get("metadata") or {}
        keep.append({
            "case": (e.get("correlation_id") or "").replace("c4-570-%s-" % tag, ""),
            "plan": inv.get(e.get("entity_id"), e.get("entity_id")),
            "feature": e.get("feature"), "step": e.get("step"), "outcome": e.get("outcome"),
            "severity": e.get("severity"), "error_code": e.get("error_code"), "message": e.get("message"),
            "user_id": e.get("user_id"), "account_id": e.get("account_id"), "entity_type": e.get("entity_type"),
            "duration_ms": e.get("duration_ms"), "metadata": md,
        })
    out["events"] = keep
    json.dump(out, open(p, "w"), indent=1)
    print("attached %d plan row sets and %d events to %s" % (len(out["rows"]), len(keep), p))

def compare(a, b):
    A = json.load(open(os.path.join(HERE, "c4_570_%s.json" % a)))
    B = json.load(open(os.path.join(HERE, "c4_570_%s.json" % b)))
    same = total = 0
    for k in A["results"]:
        total += 1
        x = A["results"][k]; y = B["results"].get(k)
        if x == y: same += 1; print("SAME  " + k)
        else: print("DIFF  " + k + "\n   " + json.dumps(x)[:400] + "\n   " + json.dumps(y)[:400])
    total += 1
    if A.get("rows") == B.get("rows"): same += 1; print("SAME  rows written")
    else: print("DIFF  rows\n   %s\n   %s" % (A.get("rows"), B.get("rows")))
    total += 1
    def evkey(e):
        e = dict(e); e["metadata"] = json.loads(json.dumps(e.get("metadata")).replace('"', '"'))
        return json.dumps(e, sort_keys=True)
    ea = [evkey(e) for e in A.get("events", [])]; eb = [evkey(e) for e in B.get("events", [])]
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
