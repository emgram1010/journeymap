"""COP-12 - the REAL map chat (Journey Map Chat Agent, real AI) reads "How I work" through the
read-only tool get_how_i_work. Test admin usr2-q, map 266 (account 13). Never prints a token.
Usage: python cop12_ai_probe.py -
"""
import sys, time
from cop5_lib import *
T = token(sys.argv)
MAP = 266
t0 = time.time()
c, b = req("POST", JM + "/journey_map/%d/ai_message" % MAP, {"content": "Before we start: what are my own ways of working for preparing a weekly plan? Summarise them in two lines.", "mode": "chat"}, T, to=600)
print("(%.0fs, %s)" % (time.time() - t0, c), short(b, 900))
reply = str(b.get("reply", "")).lower()  # the chat reply only (the JSON also carries map cell updates)
check("chat answered 200", c == 200, short(b, 300))
check("it named skill #1 and its steps (last week's jobs, who is free)", ("skill #1" in reply or "skill 1" in reply) and "last week" in reply and ("free" in reply or "availab" in reply), reply[:400])
check("it did NOT say it lacks access", "don't have access" not in reply and "do not have access" not in reply, reply[:300])
done()
