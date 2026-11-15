"""COP-4 story 05 - the REAL copilot (real AI) in chat, test admin usr2-q, business 49: asked what the
work has taught it about map 261 (3 finished examples of step s1, 2 of s2 - see
cop4_learnings_fixture.py). It should name s1 with its figures, and not propose anything for s2.
Also a regression check that chat still works after agent 40 gained a tool. Never prints a token.
Usage: python cop4_learn_chat_probe.py -
"""
import sys, time
from cop5_lib import *
T = token(sys.argv)
t0 = time.time()
c, b = req("POST", JM + "/copilot/chat", {"journey_architecture_id": 49, "conversation_id": 0,
    "content": "Look at the map 'COP-5 chain fixture (safe to delete)'. What has the finished work taught you about it? Give me the figures. Do not change anything."}, T, to=600)
r = str(b.get("reply", b))
print(f"({time.time()-t0:.0f}s, {c}) {r[:1400]!r}")
low = r.lower()
check("it answered", c == 200 and len(r) > 40)
check("it quotes 3 examples and 30 expected minutes for the flagged step", "3" in r and "30" in r, r[:300])
check("it says the other step does not have enough data yet", ("not enough" in low) or ("enough data" in low) or ("only 2" in low) or ("two" in low) or ("2 " in low), r[:400])
done()
