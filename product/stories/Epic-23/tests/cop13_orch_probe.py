"""COP-13 part A - Journey Map Orchestrator before/after the model move (and prompt repair): a REAL run
through POST journey_map/{id}/invoke (the one entry that starts the orchestrator). Test admin usr2-q, account 13.
Never prints a token.  Usage: python cop13_orch_probe.py - <map_id> <label>
Pass = what the orchestrator prompt promises, as far as one auto run shows: the run answers with text and
completes; it never claims to have edited the map; it follows the session-start steps (names blockers
or runs stages, never silently invents a subject); the reply holds no corrupted-character junk.
"""
import sys, time, re
from cop5_lib import *
T = token(sys.argv)
MAP = int(sys.argv[2]); label = sys.argv[3] if len(sys.argv) > 3 else "run"
t0 = time.time()
c, b = req("POST", JM + f"/journey_map/{MAP}/invoke", {"subject_label": "Test customer Dana", "input_data": {"note": "COP-13 model check"}}, T, to=900)
out = b.get("final_output") if isinstance(b, dict) else None
txt = out if isinstance(out, str) else str(out)
print(f"[{label}] ({time.time()-t0:.0f}s, {c}) status={b.get('status') if isinstance(b, dict) else None} exec={b.get('execution_id') if isinstance(b, dict) else None}")
print(txt[:1500])
low = txt.lower()
check("the run came back with a status", c == 200 and b.get("status") in ("completed", "failed"), short(b, 160))
check("the run completed (not failed)", c == 200 and b.get("status") == "completed", b.get("status"))
check("it produced readable text", len(txt) > 60 and txt != "None", txt[:100])
check("no corrupted-character junk in the reply", "â€" not in txt and "\u00e2\u20ac" not in txt, "")
check("it did not claim to edit the map", not re.search(r"\b(i (have )?(updated|edited|changed|rewrote) (the|your) map)\b", low), "")
check("it either named blockers/warnings, asked for what it needs, or ran a stage",
      any(w in low for w in ("blocker", "warning", "stage", "workflow", "validate", "ready", "subject", "information", "run")), "")
done()
