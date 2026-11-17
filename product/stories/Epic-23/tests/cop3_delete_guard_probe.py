"""COP-3 governance - the copilot's own business can't be deleted (endpoint 69, E-COP-073).
Over real HTTP as TEST admin usr2-q (account 13). WRITES: sets up account 13's copilot home once
(idempotent - a second setup is refused with E-COP-044 and the existing one is used), creates a
throwaway business and soft-deletes then hard-deletes it (the normal path must still work).
Usage:  python cop3_delete_guard_probe.py <magic-token|->
"""
import sys
from cop5_lib import *

T = token(sys.argv)

c, home = req("GET", JM + "/copilot/home", None, T)
if not home.get("has_home"):
    c, b = req("POST", JM + "/copilot/home_create", {}, T)
    check("set up the copilot's business", c == 200, short(b))
    c, home = req("GET", JM + "/copilot/home", None, T)
H_ID = home.get("journey_architecture_id", 0)
check("the account has a copilot business", H_ID != 0, short(home))

U = JM + "/journey_architecture/%d"
c, b = req("DELETE", U % H_ID, {}, T)
check("soft delete of the copilot's business -> E-COP-073", c >= 400 and "E-COP-073" in short(b), short(b))
c, b = req("DELETE", U % H_ID, {"hard": True}, T)
check("hard delete of the copilot's business -> E-COP-073", c >= 400 and "E-COP-073" in short(b), short(b))
c, home2 = req("GET", JM + "/copilot/home", None, T)
check("it is still there, maps untouched", home2.get("journey_architecture_id") == H_ID
      and len(home2.get("maps") or []) == len(home.get("maps") or []), short(home2))

c, a = req("POST", JM + "/journey_architecture", {"title": "COP-3 delete-guard throwaway"}, T)
A_ID = a.get("id", 0)
check("throwaway business created", c == 200 and A_ID, short(a))
c, b = req("DELETE", U % A_ID, {"reason": "COP-3 probe"}, T)
check("a normal business still soft-deletes", c == 200 and b.get("mode") == "soft", short(b))
c, b = req("DELETE", U % A_ID, {"hard": True}, T)
check("and hard-deletes", c == 200 and b.get("mode") == "hard", short(b))
c, b = req("DELETE", U % 999999, {}, T)
check("unknown business -> not found, unchanged", c == 404, short(b))
done()
