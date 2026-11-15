"""COP-3 — the copilot chat over real HTTP as TEST admin usr2-q (account 13). Uses business 47
(a COP-1 test workspace) and business 48 (another one). Makes real AI calls. Never prints a token.
Usage: python cop3_chat_probe.py <magic_q>
"""
import json, sys, urllib.request, urllib.error
H = "https://xdjc-i7zz-jhm2.n7e.xano.io"; JM = H + "/api:ER4MRRWZ"
def req(m, u, b=None, t=None, to=240):
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
    res.append(ok); print(("PASS  " if ok else "FAIL  ") + n + (f"   [{d}]" if d else ""))
msg = lambda b: b.get("message", "") if isinstance(b, dict) else str(b)

c, b = req("POST", JM + "/copilot/chat", {"journey_architecture_id": 47, "content": ""}, T); check("empty message -> E-COP-043", c >= 400 and "E-COP-043" in msg(b), msg(b))
c, b = req("POST", JM + "/copilot/chat", {"journey_architecture_id": 46, "content": "hi"}, T); check("another account's business -> E-COP-035", c >= 400 and "E-COP-035" in msg(b), msg(b))
c, b = req("POST", JM + "/copilot/chat", {"journey_architecture_id": 47, "content": "Which maps are in this business? Just list their titles.", "screen_context": "Approvals"}, T)
conv = b.get("conversation_id", 0)
check("chat answers for business 47", bool(c == 200 and conv and b.get("reply")), f"{c} conv={conv} reply={str(b.get('reply',''))[:160]!r}")
c, b2 = req("POST", JM + "/copilot/chat", {"journey_architecture_id": 47, "conversation_id": conv, "content": "Now tell me what is in the map called 'Copy of Scenario' in business 48 (map 240's business)."}, T)
check("asking about another business: answered without crossing", c == 200, f"reply={str(b2.get('reply',''))[:200]!r}")
c, b3 = req("POST", JM + "/copilot/chat", {"journey_architecture_id": 48, "conversation_id": conv, "content": "hi"}, T); check("reusing the conversation under another business -> E-COP-042", c >= 400 and "E-COP-042" in msg(b3), msg(b3))
c, b4 = req("GET", JM + f"/copilot/conversations?journey_architecture_id=47", None, T); check("conversation listed under 47", c == 200 and any(x["id"] == conv for x in b4.get("conversations", [])))
c, b5 = req("GET", JM + f"/copilot/conversations?journey_architecture_id=48", None, T); check("and not under 48", c == 200 and not any(x["id"] == conv for x in b5.get("conversations", [])))
c, b6 = req("GET", JM + f"/copilot/conversation_messages?conversation_id={conv}", None, T); check("messages reopen (4 = 2 turns)", c == 200 and len(b6.get("messages", [])) == 4, f"n={len(b6.get('messages', []))}")
c, b7 = req("GET", JM + "/copilot/home", None, T); check("home endpoint", c == 200 and b7.get("has_copilot") is True, str(b7)[:120])
print(f"\n{sum(res)}/{len(res)} passed")
