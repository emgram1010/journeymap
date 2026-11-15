"""COP-4 story 05 - give map 261 (test account 13, business 49) enough FINISHED steps for a pattern:
start and finish the remaining steps of its test jobs through the live record-event endpoint (the
same one the performer app uses), as test admin usr2-q. Each is finished within seconds against an
expected 30 minutes, so step s1 ends with 3 samples that all ran under - the "shorter" pattern.
The tool itself (get_map_learnings) can only be run with the Xano debug tool; results are in
EPIC-COP-4 Test results.   Usage: python cop4_learnings_fixture.py -
"""
import sys, uuid, time
from cop5_lib import *
T = token(sys.argv)
ids = [144, 145]  # the test jobs of map 261 besides job 143 (ids from list_business_jobs)
print("jobs:", ids)
for jid in ids:
    c, job = req("GET", PL + f"/work_item/{jid}", None, T)
    for t in (job.get("tasks") or []):
        if t.get("status") == "done":
            continue
        tid = t["id"]
        if t.get("status") == "not_started":
            c1, b1 = req("POST", PL + f"/work_task/{tid}/event", {"event_type": "started", "client_event_id": str(uuid.uuid4())}, T)
            check(f"job {jid} task {tid} ({t.get('stage_key')}) started", c1 == 200, short(b1, 200))
            time.sleep(2)
        c2, b2 = req("POST", PL + f"/work_task/{tid}/event", {"event_type": "completed", "client_event_id": str(uuid.uuid4())}, T)
        check(f"job {jid} task {tid} ({t.get('stage_key')}) completed", c2 == 200, short(b2, 200))
done()
