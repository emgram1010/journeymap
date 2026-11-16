"""COP-5 story 01 - the SCREEN path (the live planner endpoints, as test admin usr2-q) for the same
bad inputs the copilot's planner tools were given. Tools can only be run through the Xano debug
tool, not over HTTP, so the TOOL side is pinned here as the code each tool answered (recorded in
EPIC-COP-5 section 7). Final review R11 (2026-11-16): this is now an ALARM - each endpoint answer is
checked against the tool's code, and the script exits 1 if any differ (the two copies drifted).
Test account 13, plan 44.
Usage: python cop5_tool_vs_endpoint.py -      (reuses the cached session from cop5_lib)
"""
import sys
from cop5_lib import *
T = token(sys.argv)
PLAN = 44
# (name, method, path, body, what the TOOL answered: an error code, or "not_created")
cases = [
    ("create plan, name already used", "POST", "/workspace", {"name": "COP-5 probe plan A (safe to delete)"}, "E-PLN-001"),
    ("accept a map with no published version", "POST", f"/workspace/{PLAN}/map", {"map_ids": [243]}, "E-PLAN-004"),
    ("add job, title with HTML", "POST", "/work_item", {"workspace_id": PLAN, "journey_map_id": 261, "title": "<b>x</b>"}, "E-JOB-001"),
    ("add job, map the plan does not accept", "POST", "/work_item", {"workspace_id": PLAN, "journey_map_id": 243, "title": "x"}, "E-JOB-002"),
    ("add person, capacity 30", "POST", f"/workspace/{PLAN}/agent", {"name": "COP-5 probe person Z", "kind": "person", "daily_capacity_hours": 30}, "E-PLN-009"),
    ("add person, name already used", "POST", f"/workspace/{PLAN}/agent", {"name": "COP-5 probe person B", "kind": "person", "daily_capacity_hours": 8}, "E-PLN-007"),
    ("start day, start time 25:99", "POST", f"/workspace/{PLAN}/timeline", {"agent_id": 51, "planned_date": "2026-11-18", "start_time": "25:99"}, "E-PLN-010"),
    ("start day that exists (2026-11-17)", "POST", f"/workspace/{PLAN}/timeline", {"agent_id": 51, "planned_date": "2026-11-17"}, "not_created"),
    ("schedule a step already scheduled", "POST", "/work_task/865/schedule", {"timeline_id": 55}, "E-SCHED-001"),
]
for name, m, path, body, tool_said in cases:
    c, b = req(m, PL + path, body, T)
    if tool_said == "not_created":
        ok = c == 200 and isinstance(b, dict) and b.get("created") is False
    else:
        ok = c >= 400 and tool_said in short(b)
    check(f"{name}: endpoint matches the tool ({tool_said})", ok, f"{c} {short(b, 300)}")
done()
