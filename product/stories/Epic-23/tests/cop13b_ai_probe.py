"""COP-13 part B - the REAL copilot (real AI, Anthropic billed) asks to step up, the owner approves, and
the same turn is re-done on the strong copy (Opus 5.5). Test admin usr2-q, account 13, business 49.
Level for step_up_model is the default "waits for you". Never prints a token.
Usage: python cop13b_ai_probe.py -
"""
import sys, time
from cop5_lib import *
T = token(sys.argv)
ARCH = 49

def say(text, conv=0):
    t0 = time.time()
    c, b = req("POST", JM + "/copilot/chat", {"journey_architecture_id": ARCH, "conversation_id": conv, "content": text}, T, to=900)
    reply = str(b.get("reply", b))
    print(f"\n> {text}\n  ({time.time()-t0:.0f}s, {c}, stepped_up={b.get('stepped_up')}) {reply[:600]!r}")
    return c, b, reply.lower()

def waiting_step_ups():
    c, b = req("GET", MEM + "/copilot/actions", t=T)
    items = b.get("waiting", []) if isinstance(b, dict) else b
    return [a for a in (items or []) if isinstance(a, dict) and a.get("action_type") == "step_up_model" and a.get("status") == "waiting"]

# A. everyday question: no step-up
c, b, r = say("In one line: what business are we working on?")
check("A an everyday question runs on the standard copy (no step-up)", c == 200 and b.get("stepped_up") is False, r[:200])

# B. the copilot asks; it waits for the owner
before = {a["id"] for a in waiting_step_ups()}
c, b, r = say("This is a test of the stronger model. Please call request_step_up now with the reason 'owner-requested test of the stronger model', then tell me what happened.")
conv = b.get("conversation_id", 0)
new = [a for a in waiting_step_ups() if a["id"] not in before]
check("B a step-up item is waiting for the owner", len(new) == 1, [(a.get("id"), a.get("summary", "")[:80]) for a in new])
check("B the item shows the reason and the price difference", bool(new) and "twice the price" in (new[0].get("summary") or "") and "owner-requested test" in (new[0].get("summary") or ""), new[0].get("summary") if new else None)
check("B the copilot says it is waiting, and nothing stepped up yet", c == 200 and b.get("stepped_up") is False and ("wait" in r or "approv" in r), r[:300])

# C. the owner approves; the copilot re-sends it; the turn is re-done on the strong copy
aid = new[0]["id"] if new else 0
c, d = req("POST", MEM + "/copilot/action_decide", {"action_id": aid, "decision": "approve"}, T)
check("C the owner approves it", c == 200, short(d, 200))
c, b, r = say("I approved the stronger model, item %d. Please use get_approval and then call request_step_up again with that approval_id and exactly the same input. Then answer in one line: what is 17 times 23?" % aid, conv)
check("C the same turn was re-done on the strong copy (stepped_up true)", c == 200 and b.get("stepped_up") is True, r[:300])
check("C the answer is still right", "391" in r, r[:200])

print("\nconversation_id:", conv, " approval item:", aid)
done()
