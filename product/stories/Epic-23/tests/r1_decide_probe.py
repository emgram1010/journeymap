"""Final review R1 - the owner decides a waiting copilot action through the REAL endpoint
(POST copilot/action_decide, 639), as the test admin. WRITES: it approves or rejects that item.
Usage:  python r1_decide_probe.py <magic-token|-> <action_id> <approve|reject>
"""
import sys
from cop5_lib import *

T = token(sys.argv)
action_id = int(sys.argv[2])
decision = sys.argv[3]
c, b = req("POST", MEM + "/copilot/action_decide", {"action_id": action_id, "decision": decision}, T)
check("decide %s on item %d answers 200" % (decision, action_id), c == 200, short(b))
status = (b.get("action") or b).get("status") if isinstance(b, dict) else None
print("status now:", status)
done()
