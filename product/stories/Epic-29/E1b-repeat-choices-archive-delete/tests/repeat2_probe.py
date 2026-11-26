"""REPEAT-2 - live probe over real HTTP in the test account (13): what a repeat carries, archive and
restore, and the admin-only delete. Source plan 115 has people, a day, jobs, slots AND history, so it
is the plan that must never be deletable; every copy made here is a draft with no history.
Never prints a token. Every plan it makes is deleted again in phase 2.

Phase 1:  python repeat2_probe.py 1 <magic token admin usr2-q> <magic token member usr2-p>
          (prints the copy ids; the row counts of one copy are then taken with a scratch function)
Phase 2:  python repeat2_probe.py 2
"""
import json, sys, time, datetime, os, urllib.request, urllib.error

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
H = "https://xdjc-i7zz-jhm2.n7e.xano.io"
AUTH = H + "/api:RPonubWS"
PL = H + "/api:PE5iDldw:v1"
SRC = 115
OTHER_ACCOUNT_PLAN = 145
STATE = os.path.join(os.environ.get("TEMP", "."), "repeat2_probe_state.json")
res = []


def http(method, url, body=None, tok=None):
    r = urllib.request.Request(url, data=json.dumps(body).encode() if body is not None else None, method=method)
    r.add_header("Content-Type", "application/json")
    if tok:
        r.add_header("Authorization", "Bearer " + tok)
    try:
        raw = urllib.request.urlopen(r, timeout=240).read()
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


def done():
    print("\n%d/%d passed" % (sum(res), len(res)))
    sys.exit(0 if all(res) else 1)


phase = sys.argv[1]

if phase == "1":
    A = login(sys.argv[2], "usr2-q@example.com")
    M = login(sys.argv[3], "usr2-p@example.com")
    n = int(time.time() // 60) % 2000

    def D(i):  # far-future Mondays, different every run
        return (datetime.date(2030, 1, 7) + datetime.timedelta(days=14 * (n * 10 + i))).isoformat()

    tag = str(int(time.time()))

    def preview(extra):
        return http("POST", f"{PL}/workspace/{SRC}/repeat-preview", {"start_date": D(0), **extra}, A)

    def create(i, label, extra):
        return http("POST", f"{PL}/workspace/{SRC}/repeat", {"start_date": D(i), "name": f"R2 {label} {tag} (safe to delete)", **extra}, A)

    st, src_before = http("GET", f"{PL}/workspace/{SRC}/delete-check", None, A)

    print("== what comes along: preview ==")
    st, base = preview({})
    b = base.get("counts", {})
    check("preview with nothing unticked works and has people, jobs and slots", st == 200 and b.get("people", 0) > 0 and b.get("jobs", 0) > 0 and b.get("slots", 0) > 0, base)
    check("a caller that says nothing copies everything", base.get("choices") == {"skip_people": False, "skip_jobs": False, "skip_assignments": False}, base.get("choices"))
    st, p = preview({"skip_jobs": True}); c = p.get("counts", {})
    check("T-01-2 jobs unticked: 0 jobs, people and days stay", st == 200 and c.get("jobs") == 0 and c.get("people") == b["people"] and c.get("days") == b["days"], c)
    st, p = preview({"skip_assignments": True}); c = p.get("counts", {})
    check("T-01-3 assignments unticked: 0 days, 0 slots, jobs and people stay", st == 200 and c.get("days") == 0 and c.get("slots") == 0 and c.get("backlog") == 0 and c.get("slots_to_backlog") == 0 and c.get("jobs") == b["jobs"] and c.get("people") == b["people"], c)
    st, p = preview({"skip_people": True, "skip_assignments": False}); c = p.get("counts", {})
    check("T-01-4 people unticked: no people, and the server forces assignments off", st == 200 and c.get("people") == 0 and c.get("days") == 0 and c.get("slots") == 0 and p.get("choices", {}).get("skip_assignments") is True and c.get("jobs") == b["jobs"], (c, p.get("choices")))

    print("\n== what comes along: the copy ==")
    st, full = create(1, "full", {}); fc = full.get("counts", {})
    check("T-01-1 everything ticked equals the preview", st == 200 and full.get("outcome") == "created" and fc.get("people") == b["people"] and fc.get("days") == b["days"] and fc.get("jobs", {}).get("repeated") == b["jobs"] and fc.get("slots", {}).get("placed") == b["slots"], full)
    st, nj = create(2, "nojobs", {"skip_jobs": True}); c = nj.get("counts", {})
    check("T-01-2 copy with jobs unticked: no jobs, people and days kept, no warning", st == 200 and c.get("jobs", {}).get("repeated") == 0 and c.get("people") == b["people"] and c.get("days") == b["days"] and nj.get("warnings") == [], nj)
    st, na = create(3, "noassign", {"skip_assignments": True}); c = na.get("counts", {})
    check("T-01-3 copy with assignments unticked: jobs and people, no days, no slots", st == 200 and c.get("days") == 0 and c.get("slots", {}).get("placed") == 0 and c.get("slots", {}).get("backlog") == 0 and c.get("jobs", {}).get("repeated") == b["jobs"] and c.get("people") == b["people"], na)
    st, bd = http("GET", f"{PL}/workspace/{na.get('workspace_id')}/board", None, A)
    check("its board really has people, no days and no slots, no review marks", st == 200 and len(bd.get("agents", [])) == b["people"] and bd.get("timelines") == [] and bd.get("tasks") == [] and bd.get("reviews") == [], (len(bd.get("agents", [])), len(bd.get("timelines", [])), len(bd.get("tasks", []))))
    st, np_ = create(4, "nopeople", {"skip_people": True}); c = np_.get("counts", {})
    check("T-01-4 copy with people unticked: no people, no days, no slots, jobs kept, nobody named as left out", st == 200 and c.get("people") == 0 and c.get("people_left_off") == 0 and c.get("days") == 0 and c.get("jobs", {}).get("repeated") == b["jobs"] and not [x for x in np_.get("left_out", []) if x.get("kind") == "person"], np_)
    check("the choices are stored with the repeat", c.get("choices", {}).get("skip_people") is True and c.get("choices", {}).get("skip_assignments") is True, c.get("choices"))

    ids = {"full": full.get("workspace_id"), "nojobs": nj.get("workspace_id"), "noassign": na.get("workspace_id"), "nopeople": np_.get("workspace_id")}

    print("\n== archive and restore ==")
    target = ids["nojobs"]
    st, a = http("POST", f"{PL}/workspace/{target}/archive", {"is_archived": True}, A)
    listed = [w["workspace"]["id"] for w in http("GET", f"{PL}/workspace", None, A)[1].get("workspaces", [])]
    listed_all = [w["workspace"]["id"] for w in http("GET", f"{PL}/workspace?include_archived=true", None, A)[1].get("workspaces", [])]
    check("T-02-1 archive hides the plan from the list", st == 200 and target not in listed)
    check("T-02-2 'show archived' lists it", target in listed_all)
    st, bd = http("GET", f"{PL}/workspace/{target}/board", None, A)
    check("an archived plan keeps its people and days", st == 200 and len(bd.get("agents", [])) == b["people"] and len(bd.get("timelines", [])) == b["days"])
    st, a = http("POST", f"{PL}/workspace/{target}/archive", {"is_archived": False}, A)
    listed = [w["workspace"]["id"] for w in http("GET", f"{PL}/workspace", None, A)[1].get("workspaces", [])]
    check("T-02-1 restore brings it back", st == 200 and target in listed)

    print("\n== who may delete, and what ==")
    st, ck = http("GET", f"{PL}/workspace/{ids['full']}/delete-check", None, A)
    check("T-04-3 the check on a draft copy: allowed, with counts, and it frees a repeat date", st == 200 and ck.get("allowed") is True and ck.get("frees_repeat_date") is True and ck["counts"]["people"] == b["people"] and ck["counts"]["jobs"] == b["jobs"] and ck["counts"]["slots"] > 0, ck)
    st, r = http("DELETE", f"{PL}/workspace/{ids['full']}", None, M)
    check("T-03-3 a member is refused (E-USR-001)", st in (400, 403) and "E-USR-001" in str(r.get("message", "")), (st, r))
    st, bd = http("GET", f"{PL}/workspace/{ids['full']}/board", None, A)
    check("and nothing was deleted", st == 200 and len(bd.get("tasks", [])) > 0)
    st, r = http("DELETE", f"{PL}/workspace/{SRC}", None, A)
    check("T-03-5 a plan with published days is refused: archive instead (E-P3A-001)", st == 400 and "E-P3A-001" in str(r.get("message", "")) and "Archive it instead" in str(r.get("message", "")), (st, r))
    st, ck = http("GET", f"{PL}/workspace/{SRC}/delete-check", None, A)
    check("T-04-3 the check on that plan says no, with the reason", st == 200 and ck.get("allowed") is False and ck.get("code") == "E-P3A-001", ck)
    st, r = http("DELETE", f"{PL}/workspace/{OTHER_ACCOUNT_PLAN}", None, A)
    check("T-03-7 another account's plan: not found", st == 404, (st, r))
    st, r = http("GET", f"{PL}/workspace/{OTHER_ACCOUNT_PLAN}/delete-check", None, A)
    check("and its check is not found either", st == 404, (st, r))
    st, r = http("DELETE", f"{PL}/workspace/{ids['full']}", None, None)
    check("no sign-in: refused", st == 401, st)

    json.dump({"A": A, "ids": ids, "dates": {"full": D(1), "child": D(6)}, "tag": tag, "src_before": src_before, "people": b["people"], "jobs": b["jobs"]}, open(STATE, "w"))
    print("\ncopies:", ids)
    done()

if phase == "2":
    S = json.load(open(STATE))
    A, ids = S["A"], S["ids"]

    print("== delete a draft copy ==")
    st, r = http("DELETE", f"{PL}/workspace/{ids['full']}", None, A)
    d = r.get("deleted", {})
    check("T-03-1 an admin deletes a draft plan with people, days, jobs and slots", st == 200 and r.get("left_behind") == 0 and d.get("people") == S["people"] and d.get("jobs") == S["jobs"] and d.get("slots", 0) > 0 and d.get("steps", 0) > 0 and d.get("reviews", 0) > 0 and d.get("repeat_rows") == 1 and r.get("freed_repeat_date") is True, (st, r))
    st, bd = http("GET", f"{PL}/workspace/{ids['full']}/board", None, A)
    check("the plan is gone", st == 404, st)
    st, r = http("DELETE", f"{PL}/workspace/{ids['full']}", None, A)
    check("deleting it twice: not found", st == 404, st)

    print("\n== repeat again to the same date ==")
    st, again = http("POST", f"{PL}/workspace/{SRC}/repeat", {"start_date": S["dates"]["full"], "name": f"R2 again {S['tag']} (safe to delete)"}, A)
    check("T-04-1 the same plan repeats to the same date again", st == 200 and again.get("outcome") == "created" and again.get("workspace_id") not in (0, ids["full"]), again)
    ids["again"] = again.get("workspace_id")

    print("\n== the original of a copy is deleted ==")
    st, child = http("POST", f"{PL}/workspace/{ids['noassign']}/repeat", {"start_date": S["dates"]["child"], "name": f"R2 child {S['tag']} (safe to delete)"}, A)
    check("a copy can itself be repeated", st == 200 and child.get("outcome") == "created", child)
    ids["child"] = child.get("workspace_id")
    st, r = http("DELETE", f"{PL}/workspace/{ids['noassign']}", None, A)
    check("its original (a draft with jobs, no days) is deleted", st == 200 and r.get("left_behind") == 0, (st, r))
    st, hist = http("GET", f"{PL}/workspace/{ids['child']}/repeat-history", None, A)
    check("T-04-2 the copy still opens and says its original no longer exists", st == 200 and (hist.get("repeated_from") or {}).get("exists") is False, hist)
    st, bd = http("GET", f"{PL}/workspace/{ids['child']}/board", None, A)
    check("and its board still loads", st == 200 and len(bd.get("agents", [])) == S["people"])

    print("\n== clean up, and the source is untouched ==")
    for k in ("nojobs", "nopeople", "again", "child"):
        st, r = http("DELETE", f"{PL}/workspace/{ids[k]}", None, A)
        check(f"copy '{k}' deleted, nothing left behind", st == 200 and r.get("left_behind") == 0, (st, r))
    st, src_after = http("GET", f"{PL}/workspace/{SRC}/delete-check", None, A)
    check("T-03-2 the source plan lost nothing (same counts as before)", src_after.get("counts") == S["src_before"].get("counts"), (S["src_before"].get("counts"), src_after.get("counts")))
    st, hist = http("GET", f"{PL}/workspace/{SRC}/repeat-history", None, A)
    mine = [t for t in hist.get("repeated_to", []) if S["tag"] in t.get("name", "")]
    check("the source's history lists none of the deleted copies", mine == [], mine)
    os.remove(STATE)
    done()
