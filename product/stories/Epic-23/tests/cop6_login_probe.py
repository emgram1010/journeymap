"""COP-6 story 02 - logins are write-only and encrypted. Real HTTP, as TEST admin usr2-q (account 13).
Business 49 (account 13), business 46 (another account). Uses a FAKE secret with a unique marker and
hunts for it in every response (FT-COP-6-02, response half; the log half is checked with the Xano tools).
Usage:  python cop6_login_probe.py <magic-token|->            (server key NOT set: proves nothing is stored)
        python cop6_login_probe.py <magic-token|-> --keyed    (server key set: full set/replace/remove cycle)
Never prints a token. The fake secret is not a real login for anything.
"""
import sys, time
from cop5_lib import *

T = token(sys.argv)
keyed = "--keyed" in sys.argv
stamp = int(time.time())
FAKE = "FAKE-SECRET-%d-zq" % stamp
FAKE2 = "FAKE-SECRET-%d-replaced" % stamp
seen = []

def call(m, u, b=None):
    c, r = req(m, u, b, T)
    seen.append(short(r, 100000))
    return c, r

c, b = call("POST", MEM + "/copilot/connection", {"key": "login-probe-%d" % stamp, "name": "Login probe", "description": "COP-6 story 02 probe (safe to retire)"})
cid = b.get("id", 0) if isinstance(b, dict) else 0
check("library entry for the probe", c == 200 and cid, short(b))
L = MEM + "/copilot/connection_login"

c, b = call("POST", L, {"journey_architecture_id": 49, "connection_id": cid, "login": "   "})
check("blank login -> E-COP-068", c >= 400 and "E-COP-068" in short(b), short(b))
c, b = call("POST", L, {"journey_architecture_id": 46, "connection_id": cid, "login": FAKE})
check("another account's business -> E-COP-035", c >= 400 and "E-COP-035" in short(b), short(b))
c, b = call("POST", L, {"journey_architecture_id": 49, "connection_id": 999999, "login": FAKE})
check("unknown connection -> E-COP-065", c >= 400 and "E-COP-065" in short(b), short(b))

def listed():
    c, b = call("GET", MEM + "/copilot/connections?journey_architecture_id=49")
    rows = [r for r in (b.get("connections", []) if isinstance(b, dict) else []) if r.get("id") == cid]
    return rows[0] if rows else {}

if not keyed:
    c, b = call("POST", L, {"journey_architecture_id": 49, "connection_id": cid, "login": FAKE})
    check("no server key -> E-COP-067, nothing stored", c >= 400 and "E-COP-067" in short(b), short(b))
    check("still no login listed", listed().get("has_login") is False)
else:
    c, b = call("POST", L, {"journey_architecture_id": 49, "connection_id": cid, "login": FAKE})
    check("set -> 200, says only has_login", c == 200 and b.get("has_login") is True and set(b) == {"journey_architecture_id", "connection_id", "has_login"}, short(b))
    check("listed with a login", listed().get("has_login") is True)
    c, b = call("POST", MEM + "/copilot/connection_switch", {"journey_architecture_id": 49, "connection_id": cid, "is_on": True})
    check("switch ON now allowed -> 200", c == 200 and b.get("is_on") is True, short(b))
    c, b = call("POST", L, {"journey_architecture_id": 49, "connection_id": cid, "login": FAKE2})
    check("replace -> 200", c == 200 and b.get("has_login") is True, short(b))
    c, b = call("POST", L, {"journey_architecture_id": 49, "connection_id": cid, "remove": True})
    check("remove -> 200, no login", c == 200 and b.get("has_login") is False, short(b))
    row = listed()
    check("after remove: no login and switched OFF", row.get("has_login") is False and row.get("is_on") is False, str(row))

c, b = call("POST", L, {"journey_architecture_id": 49, "connection_id": cid, "remove": True})
check("removing when there is none -> 200", c == 200 and b.get("has_login") is False, short(b))
check("no response ever carried the fake secret", not any(("FAKE-SECRET-%d" % stamp) in s for s in seen))
print("connection id:", cid, " marker:", "FAKE-SECRET-%d" % stamp)
done()
