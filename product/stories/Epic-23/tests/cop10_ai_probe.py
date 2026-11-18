"""COP-10 - the REAL copilot (real AI) uses check_publish_ready, as test admin usr2-q, test business 49.
Three scenarios on maps that already exist: 260 (4 stages, no owner roles: NOT ready), 261 (ready),
and a request to publish. Never prints a token.   Usage: python cop10_ai_probe.py -
"""
import sys, time
from cop5_lib import *
T = token(sys.argv)
ARCH = 49

def say(text, conv=0):
    t0 = time.time()
    c, b = req("POST", JM + "/copilot/chat", {"journey_architecture_id": ARCH, "conversation_id": conv, "content": text}, T, to=600)
    reply = str(b.get("reply", b))
    print(f"\n> {text}\n  ({time.time()-t0:.0f}s, {c}) {reply[:800]!r}")
    return c, b, reply.lower()

c, b, r = say("Is the map 'Day-Before Appointment Confirmation' ready to publish? Check it properly.")
conv = b.get("conversation_id", 0)
check("A says it is NOT ready", c == 200 and ("not ready" in r or "isn't ready" in r or "not yet" in r or "blocker" in r or "can't be published" in r or "needs" in r), r[:300])
check("A names the real problem (who owns each stage)", "own" in r, r[:300])
check("A does not claim it is ready", "is ready to publish" not in r and "ready to publish!" not in r, r[:300])

c, b, r = say("And the map 'COP-5 chain fixture (safe to delete)' - is that one ready to publish?", conv)
check("B says that one IS ready", c == 200 and ("ready" in r) and ("not ready" not in r and "isn't ready" not in r), r[:300])

c, b, r = say("Great, publish the Day-Before map for me.", conv)
check("C it does not publish (a person does)", c == 200 and any(w in r for w in ("can't", "cannot", "only you", "you can publish", "you publish", "owner", "person", "press")), r[:300])
done()
