"""COP-6 story 01 - connections library over real HTTP, as TEST admin usr2-q (account 13).
Business 49 (account 13) and business 46 (another account). WRITES: adds library entries with a
unique key each run. No logins exist, so switching ON must be refused (E-COP-062).
Usage:  python cop6_connections_probe.py <magic-token|->
"""
import sys, time
from cop5_lib import *

T = token(sys.argv)
key = "probe-%d" % int(time.time())

c, b = req("POST", MEM + "/copilot/connection", {"key": "Bad Key", "name": "x"}, T)
check("bad key -> E-COP-064", c >= 400 and "E-COP-064" in short(b), short(b))
c, b = req("POST", MEM + "/copilot/connection", {"key": key, "name": "Probe booking tool", "description": "COP-6 probe (safe to retire)"}, T)
check("add to library -> 200", c == 200 and b.get("key") == key, short(b))
cid = b.get("id", 0) if isinstance(b, dict) else 0
c, b = req("POST", MEM + "/copilot/connection", {"key": key, "name": "Again"}, T)
check("same key again -> E-COP-066", c >= 400 and "E-COP-066" in short(b), short(b))

c, b = req("GET", MEM + "/copilot/connections?journey_architecture_id=49", None, T)
rows = b.get("connections", []) if isinstance(b, dict) else []
mine = [r for r in rows if r.get("id") == cid]
check("list shows it, off, no login", len(mine) == 1 and mine[0]["is_on"] is False and mine[0]["has_login"] is False, short(b))
check("the list never carries a login value", "secret" not in short(b, 100000).lower(), "")
c, b = req("GET", MEM + "/copilot/connections?journey_architecture_id=46", None, T)
check("another account's business -> E-COP-035", c >= 400 and "E-COP-035" in short(b), short(b))

c, b = req("POST", MEM + "/copilot/connection_switch", {"journey_architecture_id": 49, "connection_id": cid, "is_on": True}, T)
check("switch ON with no login -> E-COP-062", c >= 400 and "E-COP-062" in short(b), short(b))
c, b = req("POST", MEM + "/copilot/connection_switch", {"journey_architecture_id": 49, "connection_id": cid, "is_on": False}, T)
check("switch OFF -> 200", c == 200 and b.get("is_on") is False, short(b))
c, b = req("POST", MEM + "/copilot/connection_switch", {"journey_architecture_id": 49, "connection_id": 999999, "is_on": False}, T)
check("unknown connection -> E-COP-065", c >= 400 and "E-COP-065" in short(b), short(b))
print("connection id:", cid)
done()
