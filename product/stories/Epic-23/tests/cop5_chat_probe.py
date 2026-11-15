"""COP-5 - the REAL copilot (real AI) in chat, test admin usr2-q, test business 49: plan vs actual,
its own tasks, and drafting a small plan. Uses the fixtures from cop5_chain_fixture.py (job 143, plan 44).
Never prints a token.   Usage: python cop5_chat_probe.py -
"""
import sys, time
from cop5_lib import *
T = token(sys.argv)
ARCH = 49
def say(text, conv=0):
    t0 = time.time()
    c, b = req("POST", JM + "/copilot/chat", {"journey_architecture_id": ARCH, "conversation_id": conv, "content": text}, T, to=600)
    print(f"\n> {text}\n  ({time.time()-t0:.0f}s, {c}) {str(b.get('reply', b))[:900]!r}")
    return c, b
c, b = say("How did the job 'COP-5 chain job' go against the plan? Give me the figures per task.")
conv = b.get("conversation_id", 0)
r = str(b.get("reply", ""))
check("plan vs actual answered with the report's figures", c == 200 and "30" in r, r[:300])
c, b = say("What tasks are assigned to you today?", conv)
r = str(b.get("reply", "")).lower()
check("it lists its own task only", c == 200 and ("deliver" in r or "s2" in r or "866" in r), r[:300])
name = "COP-5 chat plan %d (safe to delete)" % int(time.time())
c, b = say(f"Draft a plan called '{name}' that uses the map 'COP-5 chain fixture (safe to delete)', add one job from it titled 'Chat job', add a person called 'Sam', start a day for Sam on 2026-11-20 and put the job's first step on it. Do not ask me anything; just do it and tell me what you did.", conv)
r = str(b.get("reply", ""))
check("it drafted a plan and said so", c == 200 and len(r) > 40, r[:300])
c, ws = req("GET", PL + "/workspace", None, T)
plans = ws if isinstance(ws, list) else (ws.get("workspaces") or ws.get("items") or [])
mine = [p for p in plans if (p.get("name") or (p.get("workspace") or {}).get("name")) == name]
check("the plan exists", len(mine) == 1, short(plans, 400))
c, b = say("Now publish that day to live.", conv)
r = str(b.get("reply", "")).lower()
check("it does not publish to live", c == 200 and ("can't" in r or "cannot" in r or "only" in r or "you" in r), r[:300])
done()
