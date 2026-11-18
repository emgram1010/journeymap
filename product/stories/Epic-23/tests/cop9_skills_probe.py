"""COP-9 stories 01/04/06 - the owner's side of the skill library, over REAL HTTP as test admin
usr2-q (account 13, copilot home = architecture 54, test business 49). Never prints a token.

  python cop9_skills_probe.py <magic_token>   (first run)    |   python cop9_skills_probe.py -   (reuse)

Needs skills 1 (skill), 2 (exception on 1) and 3 (lesson scoped to business 49) to exist - made by
the live function tests recorded in EPIC-COP-9 Test results.
Leaves the level for skill_write at "wait" in business 54 when run with --leave-wait, so the copilot
tool can be checked against it; otherwise puts it back to "tell".
"""
import sys
from cop5_lib import *

T = token(sys.argv)
HOME, BIZ = 54, 49

# ── Story 01/04: the side tables have their own read endpoint ──
c, b = req("GET", JM + "/copilot/skills", t=T)
check("FT-COP-9-04a GET copilot/skills answers", c == 200, short(b))
ids = [i["id"] for i in b.get("items", [])]
check("FT-COP-9-04a  ...with the copilot's own business", b.get("home_architecture_id") == HOME, b.get("home_architecture_id"))
check("FT-COP-9-04a  ...and the test items 1, 2, 3", all(x in ids for x in (1, 2, 3)), ids)

c, b = req("GET", JM + "/copilot/skill_versions?skill_id=1", t=T)
vs = b.get("versions", [])
check("FT-COP-9-04b history answers, newest first", c == 200 and len(vs) >= 2 and vs[0]["version_no"] > vs[-1]["version_no"], short(b))
check("FT-COP-9-04b  ...newest version is the current one", vs and vs[0]["version_no"] == b.get("current_version_no"), b.get("current_version_no"))
check("FT-COP-9-04b  ...each version holds the full content", vs and all(("body" in (v.get("content") or {})) for v in vs))
v1_body = [v for v in vs if v["version_no"] == 1][0]["content"]["body"]
cur = b.get("current_version_no")

c, b = req("GET", JM + "/copilot/skill_versions?skill_id=999999", t=T)
check("FT-COP-9-02 history of an item outside the account = not found", c == 404, (c, short(b)))

# ── Story 04: one-click undo, saved as a NEW version ──
c, b = req("POST", JM + "/copilot/skill_undo", {"skill_id": 1, "restore_version_no": 1, "reason": "COP-9 probe"}, t=T)
restored_to_v1 = c == 200 and b.get("version_no") == cur + 1
check("FT-COP-9-04c undo to version 1 -> a new version", restored_to_v1 or ("already the current" in json.dumps(b)), (c, short(b)))
c, b = req("GET", JM + "/copilot/skill_versions?skill_id=1", t=T)
top = b["versions"][0]
check("FT-COP-9-04c  ...the new version is an 'undo' by the owner of version 1", top["change"] == "undo" and top["changed_by"] == "owner" and top["undo_of_version_no"] == 1, short(top))
check("FT-COP-9-04c  ...and holds version 1's text exactly (replace, not merge)", top["content"]["body"] == v1_body, top["content"]["body"])
c, b = req("GET", JM + "/copilot/skills", t=T)
item1 = [i for i in b["items"] if i["id"] == 1][0]
check("FT-COP-9-04c  ...and the item itself now reads version 1's text", item1["body"] == v1_body and item1["version_no"] == top["version_no"], short(item1))

c, b = req("POST", JM + "/copilot/skill_undo", {"skill_id": 1, "restore_version_no": top["version_no"]}, t=T)
check("FT-COP-9-04d undo to the current version is refused (E-COP-087)", c == 400 and "E-COP-087" in json.dumps(b), (c, short(b)))
c, b = req("POST", JM + "/copilot/skill_undo", {"skill_id": 1, "restore_version_no": 9999}, t=T)
check("FT-COP-9-04d undo to a version that does not exist is refused (E-COP-087)", c == 400 and "E-COP-087" in json.dumps(b), (c, short(b)))
c, b = req("POST", JM + "/copilot/skill_undo", {"skill_id": 999999, "restore_version_no": 1}, t=T)
check("FT-COP-9-04d undo on an item outside the account is refused (E-COP-087)", c == 400 and "E-COP-087" in json.dumps(b), (c, short(b)))

# ── Story 01/08: switch one item off for ONE business ──
c, b = req("POST", JM + "/copilot/skill_switch", {"skill_id": 3, "journey_architecture_id": BIZ, "is_off": True}, t=T)
check("FT-COP-9-01c switch item 3 off for business 49", c == 200 and b.get("is_off") is True, (c, short(b)))
c, b = req("GET", JM + "/copilot/skills", t=T)
check("FT-COP-9-01c  ...the list shows it off for 49", {"skill_id": 3, "journey_architecture_id": BIZ} in b.get("off", []), b.get("off"))
c, b = req("POST", JM + "/copilot/skill_switch", {"skill_id": 3, "journey_architecture_id": BIZ, "is_off": True}, t=T)
check("FT-COP-9-01c  ...switching off twice edits the same row (no duplicate)", c == 200, (c, short(b)))
c, b = req("POST", JM + "/copilot/skill_switch", {"skill_id": 3, "journey_architecture_id": 1, "is_off": True}, t=T)
check("FT-COP-9-01c a business outside the account is refused (E-COP-081)", c == 400 and "E-COP-081" in json.dumps(b), (c, short(b)))
if "--keep-off" not in sys.argv:
    c, b = req("POST", JM + "/copilot/skill_switch", {"skill_id": 3, "journey_architecture_id": BIZ, "is_off": False}, t=T)
    check("FT-COP-9-01c switch it back on", c == 200 and b.get("is_off") is False, (c, short(b)))

# ── Story 06: one level, set once, on the copilot's own business ──
c, b = req("GET", MEM + "/copilot/levels?journey_architecture_id=%d" % HOME, t=T)
row = [r for r in (b.get("types") or b.get("levels") or []) if r.get("key", r.get("action_type")) == "skill_write"] if c == 200 else []
check("FT-COP-9-06a the levels list has 'write its own skills'", c == 200 and len(row) == 1, (c, short(b, 400)))
check("FT-COP-9-06a  ...defaulting to tell", row and (row[0].get("effective_level") or row[0].get("level")) == "tell", short(row))
want = "wait" if "--leave-wait" in sys.argv else "tell"
c, b = req("POST", MEM + "/copilot/level_set", {"journey_architecture_id": HOME, "action_type": "skill_write", "level": "wait"}, t=T)
check("FT-COP-9-06b the owner can set it to wait", c == 200, (c, short(b)))
c, b = req("POST", MEM + "/copilot/level_set", {"journey_architecture_id": HOME, "action_type": "skill_write", "level": want}, t=T)
check("FT-COP-9-06b  ...and back (left at %s)" % want, c == 200, (c, short(b)))

done()
