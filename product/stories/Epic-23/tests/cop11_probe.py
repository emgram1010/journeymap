"""COP-11 - the lock, the settings and the read endpoint over real HTTP, as test admin usr2-q (account 13).
Never prints a token. Usage: python cop11_probe.py -
Item 10 is the COP11 test item created for this check. Leaves it locked, settings back at the defaults.
"""
import sys
from cop5_lib import *
T = token(sys.argv)
SK = 10

c, b = req("GET", JM + "/copilot/skill_meta", t=T)
rows = {i["skill_id"]: i for i in b.get("items", [])}
metas = {m["skill_id"]: m for m in b.get("metas", [])}
check("A GET skill_meta works and shows item 10 as locked, planning", c == 200 and SK in rows and metas.get(SK, {}).get("is_locked") is True and metas[SK].get("work_kind") == "planning", short(b, 300))
check("A the limits default to 50 / 4000 / 30", (b.get("max_active_items"), b.get("max_load_words"), b.get("stale_after_days")) == (50, 4000, 30), short({k: b.get(k) for k in ("max_active_items", "max_load_words", "stale_after_days")}))
check("A a brand-new item is not flagged stale", rows.get(SK, {}).get("not_used_in_days") is False, short(rows.get(SK)))

c, b = req("POST", JM + "/copilot/skill_lock", {"skill_id": SK, "locked": False}, T)
check("B owner can unlock", c == 200 and b.get("locked") is False, short(b))
v1 = b.get("version_no")
c, b = req("POST", JM + "/copilot/skill_lock", {"skill_id": SK, "locked": True}, T)
check("B owner can lock again, a new version each time", c == 200 and b.get("locked") is True and b.get("version_no") == (v1 or 0) + 1, short(b))
c, vb = req("GET", JM + "/copilot/skill_versions?skill_id=%d" % SK, t=T)
top = (vb.get("versions") or [{}])[0]
check("B the lock change is in the item's history", top.get("reason") == "locked" and top.get("changed_by") == "owner", short(top, 300))

c, b = req("POST", JM + "/copilot/skill_lock", {"skill_id": 999999, "locked": True}, T)
check("C a lock on an item that isn't in my account is refused", c != 200, short(b))

for bad in ({"max_active_items": 5, "max_load_words": 4000, "stale_after_days": 30},
            {"max_active_items": 50, "max_load_words": 500, "stale_after_days": 30},
            {"max_active_items": 50, "max_load_words": 4000, "stale_after_days": 400}):
    c, b = req("POST", JM + "/copilot/library_settings", bad, T)
    check("D out-of-bounds settings refused: %s" % list(bad.values()), c != 200, short(b))
c, b = req("POST", JM + "/copilot/library_settings", {"max_active_items": 60, "max_load_words": 5000, "stale_after_days": 45}, T)
check("D in-bounds settings saved", c == 200, short(b))
c, b = req("GET", JM + "/copilot/skill_meta", t=T)
check("D the new limits are read back", (b.get("max_active_items"), b.get("max_load_words"), b.get("stale_after_days")) == (60, 5000, 45), short(b, 200))
c, b = req("POST", JM + "/copilot/library_settings", {"max_active_items": 50, "max_load_words": 4000, "stale_after_days": 30}, T)
check("D limits put back to the defaults", c == 200, short(b))

req("GET", JM + "/copilot/skill_meta")  # no sign-in
c, b = req("GET", JM + "/copilot/skill_meta")
check("E no sign-in is refused", c in (401, 403), short(b))
done()
