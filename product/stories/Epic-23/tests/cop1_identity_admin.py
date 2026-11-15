"""COP-1 stories 01/05 — HTTP helper used to test the copilot identity, off switch and cap as TEST users
(account 13: usr2-q = admin, usr2-p = member). Tokens are kept in a local file next to this script,
never printed; run `clean` afterwards. Gate-level checks (identity, cap, off) were run with a scratch
function that minted a ticket for the copilot user and called journey/tool_gate.
"""
import json, os, sys, urllib.request, urllib.error
SP=os.path.dirname(os.path.abspath(__file__)); TF=SP+"/cop1_tokens.json"
H="https://xdjc-i7zz-jhm2.n7e.xano.io"; MEM=H+"/api:Fcgmwc6Y"
def req(method,url,body=None,tok=None,sse=False):
    r=urllib.request.Request(url,data=json.dumps(body).encode() if body is not None else None,method=method)
    r.add_header("Content-Type","application/json")
    if sse: r.add_header("Accept","application/json, text/event-stream")
    if tok: r.add_header("Authorization","Bearer "+tok)
    try:
        raw=urllib.request.urlopen(r,timeout=120).read().decode(errors="replace"); code=200
    except urllib.error.HTTPError as e:
        raw=e.read().decode(errors="replace"); code=e.code
    if sse:
        for l in raw.splitlines():
            if l.startswith("data:"):
                d=json.loads(l[5:])
                if "error" in d: return code,{"_err":d["error"]["message"]}
                t=d["result"]["content"][0]["text"]
                try: return code,json.loads(t)
                except Exception: return code,{"_err":t[:200]}
    try: return code,json.loads(raw)
    except Exception: return code,raw[:200]
cmd=sys.argv[1]
if cmd=="login":
    toks={}
    for name,email,magic in [a.split("=",2) for a in sys.argv[2:]]:
        c,b=req("POST",H+"/api:RPonubWS/reset/magic-link-login",{"magic_token":magic,"email":email}); toks[name]=b["authToken"]
    json.dump(toks,open(TF,"w")); print("logged in:",sorted(toks)); sys.exit()
T=json.load(open(TF))
def show(label,c,b): print(f"{label}: http {c} ->",json.dumps(b)[:240])
if cmd=="create":   show("q creates copilot",*req("POST",MEM+"/admin/copilot_create",{"name":"Test Copilot"},T["q"]))
if cmd=="create2":  show("q creates a SECOND copilot",*req("POST",MEM+"/admin/copilot_create",{},T["q"]))
if cmd=="member":   show("member p creates copilot",*req("POST",MEM+"/admin/copilot_create",{},T["p"]))
if cmd=="get":      show("q GET account/copilot",*req("GET",MEM+"/account/copilot",None,T["q"]))
if cmd=="team":
    c,b=req("GET",MEM+"/account/my_team_members",None,T["q"])
    print("team list:",[(m.get("id"),m.get("name"),m.get("role")) for m in b] if isinstance(b,list) else b)
if cmd=="cap":      show(f"q sets cap {sys.argv[2]}",*req("POST",MEM+"/admin/copilot_cap",{"daily_cap":int(sys.argv[2])},T["q"]))
if cmd=="capbad":   show("q sets cap -1",*req("POST",MEM+"/admin/copilot_cap",{"daily_cap":-1},T["q"]))
if cmd=="status":   show(f"q switches user {sys.argv[2]} is_active={sys.argv[3]}",*req("POST",MEM+"/admin/user_status",{"user_id":int(sys.argv[2]),"is_active":sys.argv[3]=="true"},T["q"]))
if cmd=="outside_ticket":
    # outside caller (q's token) passes some ticket: identity must stay q, never the ticket's owner
    c,b=req("POST",H+"/x2/mcp/ju0Zh1JM/mcp/stream",{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"create_journey_map","arguments":{"title":"COP-1 outside+ticket (safe to delete)","ticket":sys.argv[2]}}},T["q"],True)
    jm=(b or {}).get("journey_map",{}) if isinstance(b,dict) else {}
    print("outside call with a ticket -> new map owner:",jm.get("owner_user"),"account:",jm.get("account_id"),b.get("_err","") if isinstance(b,dict) else "")
if cmd=="clean": os.remove(TF); print("tokens removed")
