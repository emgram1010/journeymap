"""COP-2 — the owner's side of approval levels, over real HTTP, as TEST users in account 13
(usr2-q = admin, usr2-p = member). Expects waiting items created beforehand by the copilot
(user 26) through copilot/action_gate: 2 (map 236, written since → out of date), 4 (approve),
5 (edit), 6 (double-approve race), 1 (reject), 3 (told). Never prints a token.
Usage: python cop2_approvals_probe.py <magic_q> <magic_p>
"""
import json, sys, urllib.request, urllib.error, concurrent.futures as cf
H = "https://xdjc-i7zz-jhm2.n7e.xano.io"; MEM = H + "/api:Fcgmwc6Y"

def req(m, u, b=None, t=None):
    r = urllib.request.Request(u, data=json.dumps(b).encode() if b is not None else None, method=m)
    r.add_header("Content-Type", "application/json")
    if t: r.add_header("Authorization", "Bearer " + t)
    try: return 200, json.loads(urllib.request.urlopen(r, timeout=60).read())
    except urllib.error.HTTPError as e:
        raw = e.read().decode(errors="replace")
        try: return e.code, json.loads(raw)
        except Exception: return e.code, {"message": raw[:200]}

def login(magic, email):
    return req("POST", H + "/api:RPonubWS/reset/magic-link-login", {"magic_token": magic, "email": email})[1]["authToken"]

Q = login(sys.argv[1], "usr2-q@example.com"); P = login(sys.argv[2], "usr2-p@example.com")
res = []
def check(name, ok, detail=""):
    res.append(ok); print(("PASS  " if ok else "FAIL  ") + name + (f"   [{detail}]" if detail else ""))
code = lambda b: (b.get("message", "") if isinstance(b, dict) else str(b))
decide = lambda i, d, t=Q, e=None: req("POST", MEM + "/copilot/action_decide", {"action_id": i, "decision": d, **({"edited_payload": e} if e is not None else {})}, t)

c, b = req("GET", MEM + "/copilot/actions", None, Q)
ids = sorted(a["id"] for a in b.get("waiting", []))
check("inbox lists the waiting items", c == 200 and {2, 4, 5, 6} <= set(ids), f"waiting={ids}")
check("inbox shows the exact payload", any(a["id"] == 4 and a["payload"].get("text") == "COP-2 approve test" for a in b.get("waiting", [])))
c, b2 = req("GET", MEM + "/copilot/actions_count", None, P)
check("member sees the badge count", c == 200 and b2.get("waiting", 0) >= 1, str(b2))
c, b3 = req("GET", MEM + "/copilot/actions", None, P)
check("member cannot open the inbox", c >= 400, f"http {c}")
c, b4 = decide(4, "approve", P)
check("member cannot decide", c >= 400, f"http {c} {code(b4)[:60]}")

c, b = decide(1, "reject"); check("reject → rejected (or already rejected on a re-run)", (c == 200 and b.get("status") == "rejected") or "E-COP-021" in code(b), f"{c} {code(b)[:60]}")
c, b = decide(1, "approve"); check("deciding again → E-COP-021", c >= 400 and "E-COP-021" in code(b), code(b))
c, b = decide(2, "approve"); check("map changed since draft → E-COP-022", c >= 400 and "E-COP-022" in code(b), code(b))
c, b = decide(4, "maybe"); check("bad decision → E-COP-032", c >= 400 and "E-COP-032" in code(b), code(b))
c, b = decide(5, "edit"); check("edit with no content → E-COP-033", c >= 400 and "E-COP-033" in code(b), code(b))
c, b = decide(4, "approve"); check("approve → approved", c == 200 and b.get("status") == "approved", f"{c} {b}")
c, b = decide(5, "edit", Q, {"to": "B", "text": "COP-2 edit test (edited by owner)"}); check("edit → edited", c == 200 and b.get("status") == "edited", f"{c} {b}")
c, b = decide(999999, "approve"); check("unknown item → E-COP-029", c >= 400 and "E-COP-029" in code(b), code(b))

with cf.ThreadPoolExecutor(4) as ex:
    outs = list(ex.map(lambda _: decide(6, "approve"), range(4)))
wins = [o for o in outs if o[0] == 200]
check("4 parallel approves → exactly one wins", len(wins) == 1, f"codes={[o[0] for o in outs]}")

c, b = req("GET", MEM + "/copilot/levels?journey_architecture_id=0", None, Q)
types = {t["key"]: t for t in b.get("types", [])}
check("levels list has all 10 types", c == 200 and len(types) == 10, f"{c} {len(types)}")
check("publish version shows locked + person-only", types.get("map_publish_version", {}).get("locked") is True and types["map_publish_version"].get("person_only") is True)
lvl = lambda body: req("POST", MEM + "/copilot/level_set", body, Q)
c, b = lvl({"journey_architecture_id": 0, "action_type": "map_publish_version", "level": "own"}); check("lowering publish → E-COP-023", c >= 400 and "E-COP-023" in code(b), code(b))
c, b = lvl({"journey_architecture_id": 0, "action_type": "customer_message", "level": "own"}); check("irreversible customer type without confirm → E-COP-026", c >= 400 and "E-COP-026" in code(b), code(b))
c, b = lvl({"journey_architecture_id": 0, "action_type": "customer_message", "level": "sometimes"}); check("bad level → E-COP-034", c >= 400 and "E-COP-034" in code(b), code(b))
c, b = lvl({"journey_architecture_id": 46, "action_type": "customer_message", "level": "wait"}); check("another account's business → E-COP-035", c >= 400 and "E-COP-035" in code(b), code(b))
c, b = req("POST", MEM + "/copilot/level_set", {"journey_architecture_id": 0, "action_type": "note_internal", "level": "wait"}, P); check("member cannot set a level", c >= 400, f"http {c}")
c, b = lvl({"journey_architecture_id": 0, "action_type": "money_payment", "level": "wait", "limit_amount": 100}); check("money limit 100 saved", c == 200 and b.get("limit_amount") == 100, f"{c} {b}")
c, b = req("POST", MEM + "/copilot/action_seen", {"action_id": 3}, Q); check("mark told item seen", c == 200, f"{c} {b}")
print(f"\n{sum(res)}/{len(res)} passed")
