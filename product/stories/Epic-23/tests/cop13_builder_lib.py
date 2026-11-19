"""Helpers for the COP-13 Builder probe: make a fixture map through the MCP door (no AI), run a build phase
through ai_message builder_mode, and read the cells back. Test admin usr2-q, account 13. Never prints a token."""
import json, urllib.request
from cop5_lib import *

import time as _t

def retry_req(*a, **k):
    """req(), retried on a gateway error (502/503/504) - Xano infrastructure, not the agent."""
    for i in range(3):
        c, b = req(*a, **k)
        if c not in (502, 503, 504): return c, b
        _t.sleep(8)
    return c, b

def mcp(T, name, args):
    body = {"jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": {"name": name, "arguments": args}}
    r = urllib.request.Request(H + "/x2/mcp/ju0Zh1JM/mcp/stream", data=json.dumps(body).encode(), method="POST")
    r.add_header("Content-Type", "application/json"); r.add_header("Accept", "application/json, text/event-stream"); r.add_header("Authorization", "Bearer " + T)
    for i in range(3):
        try:
            raw = urllib.request.urlopen(r, timeout=180).read().decode(errors="replace"); break
        except urllib.error.HTTPError as e:
            if e.code not in (502, 503, 504) or i == 2: raise
            _t.sleep(8)
    for l in raw.splitlines():
        if l.startswith("data:"):
            d = json.loads(l[5:])
            if "error" in d: return {"_err": d["error"]["message"][:300]}
            t = d["result"]["content"][0]["text"]
            try: return json.loads(t)
            except Exception: return {"_err": t[:300]}
    return {"_err": "no data"}

def make_map(T, title):
    m = mcp(T, "create_journey_map", {"title": title})["journey_map"]["id"]
    r = mcp(T, "scaffold_map", {"journey_map_id": m,
        "stage_operations": [{"action": "add", "label": "Intake"}, {"action": "add", "label": "Delivery"}, {"action": "add", "label": "Follow-up"}],
        "lens_operations": [{"action": "add", "label": "Customer view", "actor_type": "customer"}, {"action": "add", "label": "Staff view", "actor_type": "internal"}]})
    return m, r

def state(T, m):
    return mcp(T, "get_map", {"journey_map_id": m})
