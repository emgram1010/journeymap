"""COP-5 story 01 - the SCREEN path (the live planner endpoints, as test admin usr2-q) for the same
bad inputs the copilot's planner tools were given. The tool results are recorded in EPIC-COP-5
section 7 (tools can only be run through the Xano debug tool, not over HTTP); this prints the
endpoint's answer for each, so the two can be compared line by line. Test account 13, plan 44.
Usage: python cop5_tool_vs_endpoint.py -      (reuses the cached session from cop5_lib)
"""
import sys
from cop5_lib import *
T = token(sys.argv)
PLAN = 44
cases = [
    ("create plan, name already used", "POST", "/workspace", {"name": "COP-5 probe plan A (safe to delete)"}),
    ("accept a map with no published version", "POST", f"/workspace/{PLAN}/map", {"map_ids": [243]}),
    ("add job, title with HTML", "POST", "/work_item", {"workspace_id": PLAN, "journey_map_id": 261, "title": "<b>x</b>"}),
    ("add job, map the plan does not accept", "POST", "/work_item", {"workspace_id": PLAN, "journey_map_id": 243, "title": "x"}),
    ("add person, capacity 30", "POST", f"/workspace/{PLAN}/agent", {"name": "COP-5 probe person Z", "kind": "person", "daily_capacity_hours": 30}),
    ("add person, name already used", "POST", f"/workspace/{PLAN}/agent", {"name": "COP-5 probe person B", "kind": "person", "daily_capacity_hours": 8}),
    ("start day, start time 25:99", "POST", f"/workspace/{PLAN}/timeline", {"agent_id": 51, "planned_date": "2026-11-18", "start_time": "25:99"}),
    ("start day that exists (2026-11-17)", "POST", f"/workspace/{PLAN}/timeline", {"agent_id": 51, "planned_date": "2026-11-17"}),
    ("schedule a step already scheduled", "POST", "/work_task/865/schedule", {"timeline_id": 55}),
]
for name, m, path, body in cases:
    c, b = req(m, PL + path, body, T)
    msg = b.get("message") if c != 200 else {k: b.get(k) for k in ("created", "out_of_window") if k in b}
    print(f"{name}: {c} {msg}")
