"""COP-4 — goals, notes and research through the real copilot chat, as TEST admin usr2-q, in test
business 49 (COP-1 endpoint test ws). Makes real AI calls and a real web search. Never prints a token.
Usage: python cop4_think_probe.py <magic_q>
"""
import json, sys, time, urllib.request, urllib.error
H = "https://xdjc-i7zz-jhm2.n7e.xano.io"; JM = H + "/api:ER4MRRWZ"; ARCH = 49
def req(m, u, b=None, t=None, to=600):
    r = urllib.request.Request(u, data=json.dumps(b).encode() if b is not None else None, method=m)
    r.add_header("Content-Type", "application/json")
    if t: r.add_header("Authorization", "Bearer " + t)
    try: return 200, json.loads(urllib.request.urlopen(r, timeout=to).read())
    except urllib.error.HTTPError as e:
        raw = e.read().decode(errors="replace")
        try: return e.code, json.loads(raw)
        except Exception: return e.code, {"message": raw[:200]}
T = req("POST", H + "/api:RPonubWS/reset/magic-link-login", {"magic_token": sys.argv[1], "email": "usr2-q@example.com"})[1]["authToken"]
res = []
def check(n, ok, d=""):
    res.append(bool(ok)); print(("PASS  " if ok else "FAIL  ") + n + (f"   [{d}]" if d else ""))
def say(text, conv=0):
    t0 = time.time(); c, b = req("POST", JM + "/copilot/chat", {"journey_architecture_id": ARCH, "conversation_id": conv, "content": text}, T)
    print(f"  ({time.time()-t0:.0f}s) copilot: {str(b.get('reply', b))[:400]!r}")
    return c, b
c, b = say("Our goal for this business: handle twice as many bookings by June 2027. Please record it. Don't draft anything yet.")
conv = b.get("conversation_id", 0)
check("goal turn answered", c == 200 and conv)
c, b = say("Please remember this rule for this business: we never take jobs on Sundays.", conv)
check("note turn answered", c == 200)
c, m = req("GET", JM + f"/copilot/business_memory?journey_architecture_id={ARCH}", None, T)
goals = m.get("goals", []); notes = m.get("notes", [])
check("goal recorded as proposed, numbers copied not invented", any(g.get("status") == "proposed" and "2027" in (g.get("target_date", "") + g.get("goal_text", "")) for g in goals), json.dumps(goals)[:300])
check("note saved for this business", any("sunday" in n.get("note", "").lower() for n in notes), json.dumps(notes)[:200])
c, b = say("Research how equipment rental companies usually handle returns and damage checks, and draft it as maps for this business.", conv)
check("research turn answered", c == 200 and b.get("reply"))
c, m2 = req("GET", JM + f"/copilot/business_memory?journey_architecture_id={ARCH}", None, T)
profs = m2.get("map_profiles", [])
researched = [p for p in profs if p.get("made_by") == "copilot_research"]
check("researched map(s) labelled with sources and not tested", researched and all(not p.get("tested_since") for p in researched) and any(p.get("sources") for p in researched), json.dumps(researched)[:400])
c3, b3 = req("POST", JM + "/copilot/chat", {"journey_architecture_id": 48, "content": "What do you know about this business? List any notes."}, T)
check("a new conversation in business 48 does not see business 49's note", c3 == 200 and "sunday" not in str(b3.get("reply", "")).lower(), str(b3.get("reply", ""))[:200])
print(f"\n{sum(res)}/{len(res)} passed")
