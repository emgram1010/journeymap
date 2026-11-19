"""COP-13 part A - Journey Compare Analyst before/after the model move: a REAL compare turn
(real AI) on two maps of test business 49. Test admin usr2-q. Never prints a token.
Pass = what the analyst prompt promises: answered; uses the maps' real titles (not 'Scenario A/B');
never declares an overall winner; says 'no data yet' where both sides are empty; ends with a question.
Usage: python cop13_compare_probe.py - [label]
"""
import sys, time, re
from cop5_lib import *
T = token(sys.argv)
label = sys.argv[2] if len(sys.argv) > 2 else "run"
ARCH = 49
c, m = req("GET", JM + f"/copilot/business_memory?journey_architecture_id={ARCH}", t=T)
ids = [p["journey_map_id"] for p in m.get("map_profiles", []) if p.get("journey_map_id")]
print("maps in business:", ids[:6])
A, B = ids[0], ids[1]
t0 = time.time()
c, b = req("POST", JM + f"/journey_architecture/{ARCH}/compare/message", {"map_a_id": A, "map_b_id": B, "conversation_id": 0, "content": "Which of these two is healthier and why? Be brief."}, T, to=600)
reply = str(b.get("reply", b))
print(f"[{label}] ({time.time()-t0:.0f}s, {c}) {reply[:900]!r}")
low = reply.lower()
check("answered", c == 200 and len(reply) > 40, reply[:120])
check("no error text came back as the reply", not any(w in low for w in ("invalid_request", "temperature", "400", "error")), reply[:160])
check("never just 'Scenario A' / 'Scenario B'", not re.search(r"scenario [ab]", low), "")
check("does not declare an overall winner", not any(w in low for w in ("overall winner", "the winner is", "clear winner")), "")
check("says no data yet where there is none", "no data" in low or "not enough" in low or "yet" in low, "")
check("ends with a follow-up question", reply.strip().endswith("?"), reply.strip()[-80:])
done()
