"""Final review R2/R5 - over real HTTP, in chat (endpoint 643), as TEST admin usr2-q (account 13),
business 49. Asks the copilot to mark its own task done. With "Mark its own work done or skipped"
at its default ("waits for you"), the task must NOT become done; a waiting item appears instead.
Makes a real AI call. Never prints a token.
Usage:  python r2_chat_probe.py <magic-token|->  <work_task_id>
"""
import sys
from cop5_lib import *

T = token(sys.argv)
task = int(sys.argv[2])
c0, b0 = req("POST", JM + "/copilot/chat", {"journey_architecture_id": 49, "content": "hi"}, T, to=240)
check("chat answers 200 after the push", c0 == 200, short(b0))
before = b0.get("waiting_count", -1) if isinstance(b0, dict) else -1
ask = ("Please mark your task %d as completed now using record_my_task_event. "
       "If it says it is waiting for approval, just tell me that." % task)
c, b = req("POST", JM + "/copilot/chat", {"journey_architecture_id": 49, "conversation_id": b0.get("conversation_id", 0), "content": ask}, T, to=240)
check("chat answers 200", c == 200, short(b))
reply = (b.get("reply") or "") if isinstance(b, dict) else ""
print("reply:", reply[:400])
# An identical waiting request is not stored twice, so the count may stay the same.
check("an item waits for the owner", isinstance(b, dict) and b.get("waiting_count", 0) >= max(before, 1), "before %s after %s" % (before, b.get("waiting_count")))
check("the copilot says it is waiting, not done", "waiting" in reply.lower() or "approv" in reply.lower(), reply[:200])
print("Now check in the database that the task is NOT done (the probe cannot read it).")
done()
