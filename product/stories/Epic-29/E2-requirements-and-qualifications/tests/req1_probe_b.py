"""REQ-1 story 04 - live probe over real HTTP in the test account (13): what a STEP of a map needs.
Map 269 "E2E editor fixture 2" (8 stages x 5 rows; 4 internal rows do planned work, 1 row does not).
Admin = usr2-q (user 22), member = usr2-p (user 21). Never prints a token. Every need it sets is removed
again; every requirement it makes is named "R1 ..." and printed for the caller to clean up.
Usage: python req1_probe_b.py <magic admin> <magic member> <profile id to hold things> <foreign map id> <foreign cell id>
  foreign map / cell = throwaway rows the caller inserted for ANOTHER (non-existent) account.
"""
import json, sys, time, urllib.request, urllib.error

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
H = "https://xdjc-i7zz-jhm2.n7e.xano.io"
AUTH = H + "/api:RPonubWS"
JM = H + "/api:ER4MRRWZ"
CAT = H + "/api:FB308vAe"
PL = H + "/api:PE5iDldw:v1"
MAP = 269
res, made = [], {"requirements": []}


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
PROFILE, FMAP, FCELL = int(sys.argv[3]), int(sys.argv[4]), int(sys.argv[5])
tag = str(int(time.time()))[-6:]


def mkreq(name, **kw):
    st, r = http("POST", CAT + "/requirement", {"name": name, **kw}, A)
    assert st == 200 and r["outcome"] == "created", (st, r)
    made["requirements"].append(r["requirement"]["id"])
    return r["requirement"]["id"]


def needs(mapid=MAP, tok=A):
    return http("GET", f"{JM}/journey_map/{mapid}/requirement", None, tok)


def bundle(mapid):
    return http("GET", f"{JM}/journey_map/load_bundle/{mapid}", None, A)[1]


def setneed(cell, req, strength, tok=A):
    return http("POST", f"{JM}/journey_cell/{cell}/requirement", {"requirement_id": req, "strength": strength}, tok)


def dropneed(cell, req, tok=A):
    return http("DELETE", f"{JM}/journey_cell/{cell}/requirement/{req}", None, tok)


b = bundle(MAP)
lenses = {l["id"]: l for l in b["lenses"]}
planned = [l["id"] for l in b["lenses"] if l.get("actor_type") == "internal"]
unplanned = [l["id"] for l in b["lenses"] if l.get("actor_type") in ("", None)]
cells = b["cells"]
row_cells = lambda lid: [c for c in cells if c["lens"] == lid]
LP, LU = planned[0], unplanned[0]
cellP, cellP2, cellU = row_cells(LP)[0]["id"], row_cells(LP)[1]["id"], row_cells(LU)[0]["id"]
ra, rb = mkreq(f"R1 Need A {tag}"), mkreq(f"R1 Need B {tag}")

print("== story 04: what a step needs ==")
st, r = setneed(cellP, ra, "hard")
check("T-04-1 add a hard need", st == 200 and r["result"] == "added", (st, r))
st, n = needs()
mine = [x for x in n["needs"] if x["journey_cell_id"] == cellP]
check("the map's needs read shows it, with the step's stage key and row key and the name", len(mine) == 1 and mine[0]["strength"] == "hard" and mine[0]["name"].startswith("R1 Need A") and mine[0]["stage_key"] and mine[0]["lens_key"], n)
check("T-04-9 nobody holds it yet: 0 people hold it now", mine[0]["holders_now"] == 0, mine)
st, r = setneed(cellP, rb, "soft")
check("add a soft need", st == 200 and r["result"] == "added", (st, r))
st, r = setneed(cellP, ra, "soft")
check("T-04-1 switch hard to soft", st == 200 and r["result"] == "changed", (st, r))
st, r = setneed(cellP, ra, "soft")
check("T-04-2 the same need twice: no duplicate, not an error", st == 200 and r["result"] == "same", (st, r))
st, n = needs()
check("...and still exactly two needs on the step", len([x for x in n["needs"] if x["journey_cell_id"] == cellP]) == 2, n)
st, r = setneed(cellP, ra, "maybe")
check("a strength that is neither hard nor soft is refused (E-REQ-034)", st == 400 and "E-REQ-034" in msg(r), (st, r))

# holders now
st, p = http("POST", f"{PL}/agent-profile/{PROFILE}/requirement", {"requirement_id": ra, "held_until": ""}, A)
st, n = needs()
check("T-04-9 one person who holds it shows as 1 'holds it now'", [x for x in n["needs"] if x["journey_cell_id"] == cellP and x["requirement_id"] == ra][0]["holders_now"] == 1, n)
http("POST", f"{PL}/agent-profile/{PROFILE}/requirement", {"requirement_id": ra, "held_until": "2001-01-01"}, A)
st, n = needs()
check("...and an ended holding does not count", [x for x in n["needs"] if x["journey_cell_id"] == cellP and x["requirement_id"] == ra][0]["holders_now"] == 0, n)
http("DELETE", f"{PL}/agent-profile/{PROFILE}/requirement/{ra}", None, A)

st, r = setneed(cellU, ra, "hard")
check("T-04-4 a row that is not planned work refuses (E-REQ-031)", st == 400 and "E-REQ-031" in msg(r), (st, r))
st, r = http("POST", f"{JM}/journey_map/{MAP}/row-requirement", {"journey_lens_id": LU, "requirement_id": ra, "strength": "hard"}, A)
check("...and so does 'apply to the row'", st == 400 and "E-REQ-031" in msg(r), (st, r))

st, r = http("POST", f"{CAT}/requirement/{rb}/archive", {"is_archived": True}, A)
st, r = setneed(cellP2, rb, "hard")
check("T-04-5 an archived requirement cannot be newly added (E-REQ-030)", st == 400 and "E-REQ-030" in msg(r), (st, r))
st, r = setneed(cellP, rb, "hard")
check("...but where it is already set its strength can still change", st == 200 and r["result"] == "changed", (st, r))
st, n = needs()
check("...and it shows as archived", [x for x in n["needs"] if x["journey_cell_id"] == cellP and x["requirement_id"] == rb][0]["archived"] is True, n)
http("POST", f"{CAT}/requirement/{rb}/archive", {"is_archived": False}, A)

st, r = http("PATCH", f"{JM}/journey_cell/update/{cellP2}", {"is_locked": True}, A)
st, r = setneed(cellP2, ra, "hard")
check("T-04-6 a locked step refuses (E-REQ-033)", st == 400 and "E-REQ-033" in msg(r), (st, r))
st, r = dropneed(cellP2, ra)
check("...removing from a locked step refuses too", st == 400 and "E-REQ-033" in msg(r), (st, r))

print("   (whole row)")
rc = row_cells(LP)
st, r = http("POST", f"{JM}/journey_map/{MAP}/row-requirement", {"journey_lens_id": LP, "requirement_id": ra, "strength": "hard"}, A)
check("T-04-3 apply to the whole row: the locked step is skipped and named, the rest changed",
      st == 200 and r["steps_in_row"] == len(rc) and len(r["refused"]) == 1 and r["refused"][0]["journey_cell_id"] == cellP2 and r["refused"][0]["code"] == "E-REQ-033" and r["added"] + r["changed"] == len(rc) - 1, (st, r))
check("...and the count is re-read from the database", r.get("steps_with_it_now") == len(rc) - 1 + 0 or r.get("steps_with_it_now") == len(rc) - 1, r)
st, r2 = http("POST", f"{JM}/journey_map/{MAP}/row-requirement", {"journey_lens_id": LP, "requirement_id": ra, "strength": "hard"}, A)
check("...doing it again changes nothing", st == 200 and r2["added"] == 0 and r2["changed"] == 0 and r2["already_there"] == len(rc) - 1, (st, r2))
http("PATCH", f"{JM}/journey_cell/update/{cellP2}", {"is_locked": False}, A)

print("   (limit of 10)")
extra = [mkreq(f"R1 Need X{i} {tag}") for i in range(9)]
setneed(cellP2, rb, "soft")
ok_n = 0
for rid in extra:
    st, r = setneed(cellP2, rid, "soft"); ok_n += (st == 200)
st, n = needs()
count_p2 = len([x for x in n["needs"] if x["journey_cell_id"] == cellP2])
st, r = setneed(cellP2, mkreq(f"R1 Need X11 {tag}"), "soft")
check("T-04-5 a step holds at most 10 needs (E-REQ-032)", count_p2 == 10 and st == 400 and "E-REQ-032" in msg(r), (count_p2, st, r))
st, r = setneed(cellP2, rb, "hard")
check("...but changing an existing one still works at 10", st == 200 and r["result"] == "changed", (st, r))

print("   (who can see and change)")
st, r = needs(tok=M)
check("a member WITHOUT the Intelligent Layer is refused, like every other map read (E-USR-006)", st == 403 and "E-USR-006" in msg(r), (st, r))
st, r = needs(FMAP)
check("T-04-10 another account's map: its needs cannot be read", st in (403, 404), (st, r))
st, r = setneed(FCELL, ra, "hard")
check("T-04-10 ...or set", st in (403, 404), (st, r))
st, r = http("POST", f"{JM}/journey_map/{FMAP}/row-requirement", {"journey_lens_id": 1, "requirement_id": ra, "strength": "hard"}, A)
check("T-04-10 ...or applied to a row", st in (403, 404), (st, r))

print("   (needs go with their step)")
# a throwaway row: its steps are created with it; needs on them must go when the row is removed
st, ln = http("POST", f"{JM}/journey_lens/add/{MAP}", {"label": f"R1 temp row {tag}", "actor_type": "internal"}, A)
lens_new = (ln.get("journey_lens") or ln.get("lens") or ln).get("id") if st == 200 else None
check("a throwaway row to remove", bool(lens_new), (st, ln))
b2 = bundle(MAP)
tcells = [c["id"] for c in b2["cells"] if c["lens"] == lens_new]
if not tcells:
    print("   (the new row has no cells yet: using the row's first stage cell is not possible)")
for c in tcells[:2]:
    setneed(c, ra, "hard")
st, n = needs()
before = len([x for x in n["needs"] if x["journey_cell_id"] in tcells])
st, r = http("DELETE", f"{JM}/journey_lens/remove/{lens_new}", None, A)
st, n = needs()
after = len([x for x in n["needs"] if x["journey_cell_id"] in tcells])
check("T-04-8 removing a row removes the needs on its steps (none left)", before == min(2, len(tcells)) and after == 0 and st == 200, (before, after, tcells, r))

st, sg = http("POST", f"{JM}/journey_stage/add/{MAP}", {"label": f"R1 temp stage {tag}"}, A)
stage_new = (sg.get("journey_stage") or sg.get("stage") or sg).get("id") if st == 200 else None
check("a throwaway stage to remove", bool(stage_new), (st, sg))
b3 = bundle(MAP)
scells = [c["id"] for c in b3["cells"] if c["stage"] == stage_new and c["lens"] == LP]
for c in scells[:1]:
    setneed(c, ra, "hard")
st, n = needs()
before = len([x for x in n["needs"] if x["journey_cell_id"] in scells])
st, r = http("DELETE", f"{JM}/journey_stage/remove/{stage_new}", None, A)
st, n = needs()
after = len([x for x in n["needs"] if x["journey_cell_id"] in scells])
check("T-04-8 removing a stage removes the needs on its steps (none left)", before == min(1, len(scells)) and after == 0 and st == 200, (before, after, scells, r))

# clean up every need this probe set on the fixture map
st, n = needs()
for x in n["needs"]:
    if x["requirement_id"] in made["requirements"]:
        http("PATCH", f"{JM}/journey_cell/update/{x['journey_cell_id']}", {"is_locked": False}, A)
        dropneed(x["journey_cell_id"], x["requirement_id"])
st, n = needs()
check("every need the probe set is gone again", not [x for x in n["needs"] if x["requirement_id"] in made["requirements"]], n)
st, r = http("DELETE", f"{CAT}/requirement/{ra}", None, A)
check("T-01-4 and now the requirement can be deleted (nothing uses it)", st == 200, (st, r))
made["requirements"] = [i for i in made["requirements"] if i != ra]
for rid in list(made["requirements"]):
    st, r = http("DELETE", f"{CAT}/requirement/{rid}", None, A)
    if st == 200:
        made["requirements"].remove(rid)
print("requirements left to clean up:", made)
print("\n%d/%d passed" % (sum(res), len(res)))
sys.exit(0 if all(res) else 1)
