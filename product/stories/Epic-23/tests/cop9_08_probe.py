"""COP-9 story 08 - exceptions per scenario, live, as test admin usr2-q (account 13). Never prints a token.
Exception #2 (under skill #1) is switched OFF for business 49 and must stop loading there while still
loading in business 54; then it is switched back ON. A business-scoped throwaway exception (made by the
test script as the copilot) must load only in its own business. Usage: python cop9_08_probe.py -
"""
import sys
from cop5_lib import *
T = token(sys.argv)

def loaded(arch):
    c, b = req("GET", JM + "/copilot/skills", t=T)  # sanity: endpoint up
    return c

c, b = req("POST", JM + "/copilot/skill_switch", {"skill_id": 2, "journey_architecture_id": 49, "is_off": True}, T)
check("A switch exception #2 off for business 49", c == 200 and b.get("is_off") is True, short(b))
c, b = req("GET", JM + "/copilot/skills", t=T)
off = [(o["skill_id"], o["journey_architecture_id"]) for o in b.get("off", [])]
check("A the switch is stored for (2, 49) only", (2, 49) in off and (2, 54) not in off, off)
print("NEXT: run copilot/skill_library for 49 and 54 (done from the session with runWorkspaceFunction)")
done()
