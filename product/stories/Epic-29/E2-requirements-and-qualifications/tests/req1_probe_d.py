"""REQ-1 story 05 - Publish version freezes the needs, tested live over real HTTP on CLONES of a test-account
map (never the original; map 178 belongs to the founder's account, so a test-account fixture, map 261, is cloned).
Admin = usr2-q (user 22). Never prints a token. Prints the version ids and step keys so the frozen rows can be
read back through req/step_needs and cleaned up by the caller.
Usage: python req1_probe_d.py <magic admin>
"""
import json, sys, time, urllib.request, urllib.error

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
H = "https://xdjc-i7zz-jhm2.n7e.xano.io"
AUTH = H + "/api:RPonubWS"
JM = H + "/api:ER4MRRWZ"
CAT = H + "/api:FB308vAe"
SRC = 261
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
    print(("PASS  " if ok else "FAIL  ") + n + (("   [" + str(d)[:500] + "]") if d and not ok else ""))


st, d = http("POST", AUTH + "/reset/magic-link-login", {"magic_token": sys.argv[1], "email": "usr2-q@example.com"})
assert st == 200 and d.get("authToken"), "sign-in failed"
A = d["authToken"]
tag = str(int(time.time()))[-6:]
msg = lambda r: str(r.get("message", ""))


ARCH = (http("GET", f"{JM}/journey_map/load_bundle/{SRC}", None, A)[1].get("journey_map") or {}).get("journey_architecture") or 47


def clone(label):
    st, cl = http("POST", f"{JM}/journey_architecture/{ARCH}/scenarios/clone", {"source_map_id": SRC, "title": f"R1 publish {label} {tag} (safe to delete)"}, A)
    m = (cl.get("journey_map") or cl.get("map") or cl) if st == 200 else {}
    return m.get("id"), cl


def make_ready(mapid):
    """The clone does not copy stage owners or cell durations, so give the publish checklist what it asks for."""
    b = http("GET", f"{JM}/journey_map/load_bundle/{mapid}", None, A)[1]
    planned_ids = [l["id"] for l in b["lenses"] if l.get("actor_type") in ("internal", "ai_agent")]
    owner = planned_ids[0]
    owner_key = [l["key"] for l in b["lenses"] if l["id"] == owner][0]
    for sg in b["stages"]:
        http("PATCH", f"{JM}/journey_stage/update/{sg['id']}", {"label": sg["label"], "stage_goal": "R1 goal", "primary_actor_lens": owner_key, "owner_lens_id": owner}, A)
    for c in b["cells"]:
        if c["lens"] in planned_ids:
            http("PATCH", f"{JM}/journey_cell/update/{c['id']}", {"time_duration_value": 30, "time_duration_unit": "minutes"}, A)
    rd = http("GET", f"{JM}/journey_map/{mapid}/readiness", None, A)[1]
    print("   readiness of map", mapid, "->", {k: rd.get(k) for k in ("ready", "ready_count", "total")}, [(x["code"], x["stage_key"]) for x in rd.get("blockers", [])][:6])
    return rd.get("ready")


def publish(mapid):
    return http("POST", f"{JM}/journey_map/{mapid}/publish", {}, A)


def versions(mapid):
    st, v = http("GET", f"{JM}/journey_map/{mapid}/versions", None, A)
    vs = v.get("versions") if isinstance(v, dict) else v
    return vs or []


print("== a map WITH needs ==")
m1, cl = clone("with needs")
check("a clone of a test-account map", bool(m1), cl)
b = http("GET", f"{JM}/journey_map/load_bundle/{m1}", None, A)[1]
planned = [l["id"] for l in b["lenses"] if l.get("actor_type") in ("internal", "ai_agent")]
cells = [c for c in b["cells"] if c["lens"] in planned]
check("the clone has steps on planned-work rows", len(cells) >= 2, (len(b["cells"]), planned))
st, rq = http("POST", CAT + "/requirement", {"name": f"R1 pub hard {tag}"}, A)
rh = rq["requirement"]["id"]
st, rq = http("POST", CAT + "/requirement", {"name": f"R1 pub soft {tag}"}, A)
rs = rq["requirement"]["id"]
c1, c2 = cells[0]["id"], cells[1]["id"]
http("POST", f"{JM}/journey_cell/{c1}/requirement", {"requirement_id": rh, "strength": "hard"}, A)
http("POST", f"{JM}/journey_cell/{c1}/requirement", {"requirement_id": rs, "strength": "soft"}, A)
st, nd = http("GET", f"{JM}/journey_map/{m1}/requirement", None, A)
keys = [(x["stage_key"], x["lens_key"], x["requirement_id"], x["strength"]) for x in nd["needs"] if x["journey_cell_id"] == c1]
check("one hard and one soft need on a step", len(keys) == 2, nd)
stage_key, lens_key = keys[0][0], keys[0][1]

check("the clone is made ready for the publish checklist", make_ready(m1) is True)
st, p1 = publish(m1)
check("T-REQ-05-1 Publish version freezes both needs (needs_frozen = 2)", st == 200 and p1.get("needs_frozen") == 2, (st, p1 if st != 200 else {k: p1.get(k) for k in ("needs_frozen", "rates_written")}))
v1 = [v for v in versions(m1)]
check("a version now exists", len(v1) >= 1, v1)
vid1 = (p1.get("map_version") or {}).get("id") or (v1[0]["id"] if v1 else None)
print("   VERSION 1 id:", vid1, "| step keys:", stage_key, lens_key, "| requirements:", rh, rs)

print("\n== a later edit does not reach the version; a new version carries it ==")
http("DELETE", f"{JM}/journey_cell/{c1}/requirement/{rh}", None, A)
st, nd = http("GET", f"{JM}/journey_map/{m1}/requirement", None, A)
check("T-REQ-05-2 the draft no longer has the hard need", [x["requirement_id"] for x in nd["needs"] if x["journey_cell_id"] == c1] == [rs], nd)
http("POST", f"{JM}/journey_cell/{c2}/requirement", {"requirement_id": rs, "strength": "hard"}, A)
st, p2 = publish(m1)
check("T-REQ-05-3 publishing again freezes the new set (2 needs: one on each of two steps)", st == 200 and p2.get("needs_frozen") == 2, (st, p2 if st != 200 else {k: p2.get(k) for k in ("needs_frozen",)}))
vid2 = (p2.get("map_version") or {}).get("id")
print("   VERSION 2 id:", vid2)

print("\n== a map with NO needs ==")
m2, cl2 = clone("no needs")
check("another clone, no needs", bool(m2), cl2)
check("the second clone is ready too", make_ready(m2) is True)
st, p3 = publish(m2)
check("T-REQ-05-5 a map with no needs publishes with needs_frozen = 0 and no needs rows", st == 200 and p3.get("needs_frozen") == 0, (st, p3 if st != 200 else {k: p3.get(k) for k in ("needs_frozen",)}))
vid3 = (p3.get("map_version") or {}).get("id")
print("   VERSION 3 id:", vid3)

# leave the clones and the requirements for the caller to read back and clean
json.dump({"m1": m1, "m2": m2, "v": [vid1, vid2, vid3], "keys": [stage_key, lens_key], "req": [rh, rs]}, open("req1_probe_d_state.json", "w"))
print("\n%d/%d passed" % (sum(res), len(res)))
sys.exit(0 if all(res) else 1)
