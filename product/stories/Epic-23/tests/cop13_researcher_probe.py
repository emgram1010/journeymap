"""COP-13 part A - the Copilot Researcher on Sonnet 5.5: a REAL research turn through the copilot chat
(real AI + real web search). Test admin usr2-q, account 13, business 49. Never prints a token.
Pass = what the research prompt promises: answered; drafted map(s) labelled made_by copilot_research with
sources, not tested; nothing published; no business details in the searches (read from tool_call_log by the caller).
Usage: python cop13_researcher_probe.py -
"""
import sys, time
from cop5_lib import *
T = token(sys.argv)
ARCH = 49
def maps():
    c, m = req("GET", JM + f"/copilot/business_memory?journey_architecture_id={ARCH}", t=T)
    return {p.get("journey_map_id"): p for p in m.get("map_profiles", []) if p.get("made_by") == "copilot_research"}
before = set(maps())
t0 = time.time()
c, b = req("POST", JM + "/copilot/chat", {"journey_architecture_id": ARCH, "conversation_id": 0, "content": "Research how dental clinics usually handle appointment reminders and no-shows, and draft it as a map for this business."}, T, to=900)
reply = str(b.get("reply", b))
print(f"({time.time()-t0:.0f}s, {c}) {reply[:700]!r}")
check("the research turn answered", c == 200 and len(reply) > 80, reply[:120])
new = {k: v for k, v in maps().items() if k not in before}
check("a researched map was drafted", len(new) >= 1, sorted(new))
check("each is labelled with sources and not marked tested", bool(new) and all(v.get("sources") and not v.get("tested_since") for v in new.values()), short(list(new.values()), 300))
check("the report names sources and what was thin or general", ("source" in reply.lower() or "http" in reply.lower()) and any(w in reply.lower() for w in ("general", "thin", "fitted", "assum")), reply[:200])
print("new research map ids:", sorted(new), " conversation:", b.get("conversation_id"))
done()
