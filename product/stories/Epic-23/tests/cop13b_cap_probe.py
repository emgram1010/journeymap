"""COP-13 part B - the daily step-up cap is an owner setting. Test admin usr2-q, account 13, business 49.
Sets the cap to 1 (the account already asked once in the last 24h), then asks the REAL copilot to step up:
it must be refused with the daily limit, with no new waiting item. Restores the saved limits at the end.
Never prints a token.  Usage: python cop13b_cap_probe.py -
"""
import sys
from cop5_lib import *
T = token(sys.argv)
ARCH = 49

c, m = req("GET", JM + "/copilot/skill_meta", t=T)
check("meta answers and carries the cap", c == 200 and isinstance(m.get("step_up_daily_cap"), int), short(m, 200))
saved = {k: m[k] for k in ("max_active_items", "max_load_words", "stale_after_days", "trial_min_uses", "trial_max_overrides", "step_up_daily_cap")}
print("saved limits:", saved)

def save(cap):
    return req("POST", JM + "/copilot/library_settings", {**saved, "step_up_daily_cap": cap}, T)

c, b = save(21)
check("a cap of 21 is refused with a plain message", c == 400 and "between 1 and 20" in str(b), short(b, 200))
c, b = req("POST", JM + "/copilot/library_settings", {k: v for k, v in saved.items() if k != "step_up_daily_cap"}, T)
check("leaving the cap out keeps the saved value (older screens)", c == 200 and b.get("step_up_daily_cap") in (saved["step_up_daily_cap"], 0), short(b, 200))
c, b = save(1)
check("a cap of 1 is saved", c == 200 and b.get("step_up_daily_cap") == 1, short(b, 200))
c, m2 = req("GET", JM + "/copilot/skill_meta", t=T)
check("the screen reads the new cap back", m2.get("step_up_daily_cap") == 1, m2.get("step_up_daily_cap"))

def waiting():
    c, b = req("GET", MEM + "/copilot/actions", t=T)
    items = b.get("waiting", []) if isinstance(b, dict) else b
    return {a["id"] for a in (items or []) if isinstance(a, dict) and a.get("action_type") == "step_up_model" and a.get("status") == "waiting"}

try:
    before = waiting()
    c, b = req("POST", JM + "/copilot/chat", {"journey_architecture_id": ARCH, "conversation_id": 0, "content": "This is a test of the daily limit. Please call request_step_up now with the reason 'owner-requested test of the daily limit', then tell me exactly what it answered."}, T, to=900)
    r = str(b.get("reply", b)).lower()
    print("reply:", r[:500])
    check("the real copilot is refused with the daily limit", c == 200 and ("daily limit" in r or "limit" in r) and b.get("stepped_up") is False, r[:300])
    check("nothing new waits for the owner", waiting() - before == set(), sorted(waiting() - before))
finally:
    c, b = save(saved["step_up_daily_cap"])
    check("the saved cap is put back", c == 200 and b.get("step_up_daily_cap") == saved["step_up_daily_cap"], short(b, 200))
done()
