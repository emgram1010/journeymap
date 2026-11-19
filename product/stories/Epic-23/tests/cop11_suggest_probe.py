"""COP-11 "suggest instead" - the REAL copilot asks to change LOCKED skill #10 (test account 13, business 49).
The change must wait for the owner with before and after; nothing changes until approved; after approval
the copilot re-sends it, the item changes, and it stays locked. Then the probe puts #10 back with Undo.
Never prints a token.  Usage: python cop11_suggest_probe.py -
"""
import sys
sys.stdout.reconfigure(encoding="utf-8", errors="replace")
from cop5_lib import *
T = token(sys.argv)
SKILL = 10
NEW_TEXT = "COP11 suggest probe: check the locked item before planning."

def say(t, conv=0):
    c, b = req("POST", JM + "/copilot/chat", {"journey_architecture_id": 49, "conversation_id": conv, "content": t}, T, to=900)
    r = str(b.get("reply", b)); print("\n>", t[:140], "\n  ", c, repr(r[:500])); return c, b, r.lower()

def item(i):
    c, b = req("GET", JM + "/copilot/skills", t=T)
    return next((x for x in b.get("items", []) if x["id"] == i), {})

def locked(i):
    c, b = req("GET", JM + "/copilot/skill_meta", t=T)
    return any(m.get("skill_id") == i and m.get("is_locked") for m in b.get("metas", []))

def waiting_skill_items():
    c, b = req("GET", MEM + "/copilot/actions", t=T)
    items = b.get("waiting", []) if isinstance(b, dict) else b
    return [a for a in (items or []) if isinstance(a, dict) and a.get("action_type") == "skill_write" and a.get("status") == "waiting"]

before = item(SKILL)
check("setup: #10 exists and is locked", bool(before) and locked(SKILL), before.get("version_no"))
v0 = before.get("version_no")
seen = {a["id"] for a in waiting_skill_items()}

# A. the copilot asks; it waits, showing before and after; nothing changes yet
c, b, r = say(f"Skill #{SKILL} is locked. Please call save_skill to change its body to exactly '{NEW_TEXT}' (keep its title), with the reason 'probe: owner asked for a change'. Then tell me what happened.")
conv = b.get("conversation_id", 0)
# An identical earlier request is matched to its existing item, so find it by its text, not by "new".
new = [a for a in waiting_skill_items() if NEW_TEXT[:40] in (a.get("summary") or "")]
summ = (new[0].get("summary") or "") if new else ""
check("A one change to the locked item is waiting for the owner", len(new) == 1, [(a.get("id"), a.get("summary", "")[:90]) for a in new])
check("A the waiting item shows before and after", "Before:" in summ and "After:" in summ and "LOCKED" in summ, summ[:200])
mid = item(SKILL)
check("A nothing changed yet", mid.get("version_no") == v0 and mid.get("body") == before.get("body"), mid.get("version_no"))

# B. the owner approves; the copilot re-sends; the item changes and stays locked
aid = new[0]["id"] if new else 0
c2, d = req("POST", MEM + "/copilot/action_decide", {"action_id": aid, "decision": "approve"}, T)
check("B the owner approves", c2 == 200, short(d, 160))
c, b, r = say(f"I approved item {aid}. Use get_approval, then call save_skill again with approval_id {aid} and exactly the same input.", conv)
after = item(SKILL)
check("B the locked item changed to the approved text", (after.get("body") or "").strip() == NEW_TEXT and (after.get("version_no") or 0) > (v0 or 0), (after.get("version_no"), (after.get("body") or "")[:80]))
check("B it is still locked", locked(SKILL))

# C. put #10 back as it was (Undo to the version before the probe)
if (after.get("version_no") or 0) > (v0 or 0):
    cu, u = req("POST", JM + "/copilot/skill_undo", {"skill_id": SKILL, "restore_version_no": v0, "reason": "probe clean-up"}, T)
    back = item(SKILL)
    check("C clean-up: #10 is back to its old text", cu == 200 and back.get("body") == before.get("body"), short(u, 160))
print("\nconversation:", conv, " approval item:", aid)
done()
