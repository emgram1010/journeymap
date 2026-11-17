"""4-C replay set for endpoint 523 (POST /workspace, create a plan). Real HTTP as TEST admin usr2-q
(account 13). Run once BEFORE the endpoint is pointed at planner_ops/create_workspace and once AFTER;
then compare the two outputs:
    python c4_523_replay.py <magic_token|->  <label>          -> writes c4_523_<label>.json next to this file
    python c4_523_replay.py compare <labelA> <labelB>        -> diffs the two (run tag and ids normalised)
Each run uses a unique tag, so names never collide between runs. Every call that sends a
correlation_id uses "c4-<tag>-<case>", so its event_log rows can be found afterwards
(event_log is checked separately, through the Xano MCP - this script cannot read tables).
Never prints a token.
"""
import json, os, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from cop5_lib import req, token, PL

HERE = os.path.dirname(os.path.abspath(__file__))

def cases(tag):
    n = "C4 " + tag
    return [
        ("ok_full",        {"name": n + " full", "planning_window_start": "2026-12-01", "planning_window_end": "2026-12-14",
                            "input_tokens_per_minute": 1500, "output_tokens_per_minute": 300}),
        ("ok_min_no_cid",  {"name": n + " min"}),                       # every optional field left out
        ("ok_zero_rates",  {"name": n + " zero", "input_tokens_per_minute": 0, "output_tokens_per_minute": 0}),
        ("ok_80_chars",    {"name": (n + " eighty ").ljust(80, "x")}),
        ("ok_html_name",   {"name": "<b>" + n + "</b>"}),               # no HTML rule on this endpoint today
        ("ok_account_ignored", {"name": n + " acct", "account_id": 1}),
        ("ok_same_day",    {"name": n + " sameday", "planning_window_start": "2026-12-05", "planning_window_end": "2026-12-05"}),
        ("ok_only_start",  {"name": n + " onlystart", "planning_window_start": "2026-11-20"}),
        ("rej_blank",      {"name": ""}),
        ("rej_spaces",     {"name": "    "}),
        ("rej_missing_name", {}),
        ("rej_81_chars",   {"name": (n + " long ").ljust(81, "y")}),
        ("rej_end_before", {"name": n + " backwards", "planning_window_start": "2026-12-10", "planning_window_end": "2026-12-01"}),
        ("rej_neg_input",  {"name": n + " neg", "input_tokens_per_minute": -1}),
        ("rej_neg_output", {"name": n + " negout", "output_tokens_per_minute": -5}),
        ("rej_duplicate",  {"name": n + " full"}),
        ("rej_dup_padded", {"name": "  " + n + " full  "}),             # trimmed, so still a duplicate
        ("rej_order",      {"name": "", "planning_window_start": "2026-12-10", "planning_window_end": "2026-12-01"}),
        ("rej_order_spaces", {"name": "   ", "planning_window_start": "2026-12-10", "planning_window_end": "2026-12-01",
                              "input_tokens_per_minute": -1}),         # name check must win over date and rate
        ("rej_order_long_dup", {"name": (n + " long ").ljust(81, "y"), "planning_window_start": "2026-12-10",
                                "planning_window_end": "2026-12-01"}), # length wins over dates
        ("rej_bad_date",   {"name": n + " baddate", "planning_window_start": "not-a-date"}),
        ("rej_only_end_past", {"name": n + " pastend", "planning_window_end": "2020-01-01"}),
    ]

def norm(o, tag, ids):
    s = json.dumps(o, sort_keys=True).replace(tag, "<TAG>")
    o = json.loads(s)
    if isinstance(o, dict):
        w = o.get("workspace")
        if isinstance(w, dict):
            ids.append(w.get("id"))
            for k in ("id", "created_at", "updated_at"):
                if k in w: w[k] = "<" + k + ">"
    return o

def run(label):
    T = token(sys.argv)
    tag = time.strftime("%H%M%S")
    out = {"tag": tag, "label": label, "results": {}}
    for name, body in cases(tag):
        b = dict(body)
        if not name.endswith("no_cid"):
            b["correlation_id"] = "c4-%s-%s" % (tag, name)
        c, r = req("POST", PL + "/workspace", b, T)
        ids = []
        rn = norm(r, tag, ids)
        if isinstance(rn, dict) and c != 200:
            rn = {k: rn.get(k) for k in ("code", "message", "payload")}
        out["results"][name] = {"http": c, "body": rn, "workspace_id": ids[0] if ids else None}
        print("%-20s %s  %s" % (name, c, json.dumps(rn)[:160]))
    p = os.path.join(HERE, "c4_523_%s.json" % label)
    json.dump(out, open(p, "w"), indent=1)
    print("\ntag", tag, "-> saved", p)

def compare(a, b):
    A = json.load(open(os.path.join(HERE, "c4_523_%s.json" % a)))["results"]
    B = json.load(open(os.path.join(HERE, "c4_523_%s.json" % b)))["results"]
    same = 0
    for k in A:
        x = {kk: A[k][kk] for kk in ("http", "body")}; y = {kk: B.get(k, {}).get(kk) for kk in ("http", "body")}
        if x == y: same += 1; print("SAME  " + k)
        else: print("DIFF  " + k + "\n   " + json.dumps(x)[:400] + "\n   " + json.dumps(y)[:400])
    print("\n%d/%d matching" % (same, len(A)))
    sys.exit(0 if same == len(A) else 1)

if __name__ == "__main__":
    if sys.argv[1] == "compare": compare(sys.argv[2], sys.argv[3])
    else: run(sys.argv[2] if len(sys.argv) > 2 else "run")
