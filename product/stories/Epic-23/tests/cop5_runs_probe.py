"""COP-5 story 05 - scheduled runs, the SCREEN side (test admin usr2-q, account 13, business 49).
The run engine itself (copilot/scheduled_run) is not reachable over HTTP on purpose - it was driven
with the Xano function runner; results are in EPIC-COP-5 section 7. This checks what a person sees:
the level switch on the approval-levels screen and the run log endpoint.
Usage: python cop5_runs_probe.py -      (reuses the cached session from cop5_lib)
"""
import sys
from cop5_lib import *
T = token(sys.argv)
ARCH = 49

c, b = req("GET", MEM + f"/copilot/levels?journey_architecture_id={ARCH}", None, T)
rows = b.get("types") or b.get("levels") or b.get("rows") or b.get("items") or (b if isinstance(b, list) else [])
mine = [r for r in rows if (r.get("key") or r.get("action_type")) == "scheduled_work"]
check("the levels screen lists scheduled work", c == 200 and len(mine) == 1, short(b, 500))
if mine:
    r = mine[0]
    check("it is not locked, not person-only, and marked as used by the copilot", not r.get("locked") and not r.get("person_only") and r.get("wired") is True, r)
    start_level = r.get("level") or r.get("effective_level")
    print("  level now:", start_level)

c, b = req("POST", MEM + "/copilot/level_set", {"journey_architecture_id": ARCH, "action_type": "scheduled_work", "level": "wait"}, T)
check("an admin can switch it off (Waits for you)", c == 200, short(b, 300))
c, b = req("GET", JM + f"/copilot/runs?journey_architecture_id={ARCH}", None, T)
check("the run log says it is off, and still shows past runs", c == 200 and b.get("scheduled_work_on") is False and len(b.get("runs", [])) > 0, short(b, 300))

c, b = req("POST", MEM + "/copilot/level_set", {"journey_architecture_id": ARCH, "action_type": "scheduled_work", "level": "tell"}, T)
check("and back on (Runs, then tells you)", c == 200, short(b, 300))
c, b = req("GET", JM + f"/copilot/runs?journey_architecture_id={ARCH}", None, T)
check("the run log says it is on", c == 200 and b.get("scheduled_work_on") is True, short(b, 300))
runs = b.get("runs", [])
statuses = {r["status"] for r in runs}
check("the log holds finished, skipped, failed and nothing-to-do runs", {"finished", "skipped", "failed", "nothing_to_do"} <= statuses, statuses)
check("no run report contains a ticket-shaped value", not any(__import__("re").search(r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}", (r.get("report") or "") + (r.get("reason") or "")) for r in runs))
check("lock keys are not sent to the screen", not any("lock_key" in r for r in runs))

c, b = req("GET", JM + "/copilot/runs?journey_architecture_id=48", None, T)
check("another business of the account: off, and none of business 49's runs", c == 200 and b.get("scheduled_work_on") is False and not any(r.get("journey_architecture_id") == ARCH for r in b.get("runs", [])), short(b, 300))
c, b = req("GET", JM + "/copilot/runs?journey_architecture_id=1", None, T)
check("a business in another account: not found", c == 404 and "E-COP-035" in str(b.get("message")), short(b, 200))
c, b = req("GET", JM + "/copilot/runs", None, T)
check("no business given: not found", c == 404, short(b, 200))
c, b = req("GET", JM + f"/copilot/runs?journey_architecture_id={ARCH}", None, None)
check("signed out: refused", c in (401, 403), c)
done()
