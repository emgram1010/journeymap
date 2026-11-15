"""COP-1 story 06 — scaffold_map through the live tool address, as a TEST user (account 13).
Usage: python cop1_scaffold_map_probe.py <magic token for usr2-q@example.com>   (creates one "(safe to delete)" map)
"""
import json, sys, urllib.request
H="https://xdjc-i7zz-jhm2.n7e.xano.io"
def post(url,body,tok=None,sse=False):
    req=urllib.request.Request(url,data=json.dumps(body).encode(),method="POST"); req.add_header("Content-Type","application/json")
    if sse: req.add_header("Accept","application/json, text/event-stream")
    if tok: req.add_header("Authorization","Bearer "+tok)
    return urllib.request.urlopen(req,timeout=120).read().decode(errors="replace")
tok=json.loads(post(H+"/api:RPonubWS/reset/magic-link-login",{"magic_token":sys.argv[1],"email":"usr2-q@example.com"}))["authToken"]
def mcp(name,args):
    raw=post(H+"/x2/mcp/ju0Zh1JM/mcp/stream",{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":name,"arguments":args}},tok,True)
    for l in raw.splitlines():
        if l.startswith("data:"):
            d=json.loads(l[5:])
            if "error" in d: return {"_err":d["error"]["message"][:200]}
            t=d["result"]["content"][0]["text"]
            try: return json.loads(t)
            except Exception: return {"_err":t[:200]}
m=mcp("create_journey_map",{"title":"COP-1 scaffold_map fixture (safe to delete)"})["journey_map"]["id"]
res=[]
def chk(n,ok,d=""): res.append(ok); print(("PASS  " if ok else "FAIL  ")+n+(f"   [{d}]" if d else ""))
def shape(): g=mcp("get_map",{"journey_map_id":m}); return g["stages"],g["lenses"],len(g["cells"])
a=mcp("scaffold_map",{"journey_map_id":m,"stage_operations":[{"action":"add","label":"Alpha"}],"lens_operations":[{"action":"add","label":"Row one"}]})
chk("add a stage with NO primary_actor_lens or stage_goal (the reported crash)", a.get("success") is True and a.get("stages_added")==1 and a.get("lenses_added")==1, str({k:a.get(k) for k in ("stages_added","lenses_added","_err")}))
st,ln,cells=shape()
alpha=[s for s in st if s["label"]=="Alpha"]
chk("the new stage exists and the grid is complete", len(alpha)==1 and cells==len(st)*len(ln), f"stages={len(st)} lenses={len(ln)} cells={cells}")
k=alpha[0]["key"] if alpha else "s1"
b=mcp("scaffold_map",{"journey_map_id":m,"stage_operations":[{"action":"rename","key":k,"label":"Alpha goal","stage_goal":"Done when tested"}]})
b2=mcp("scaffold_map",{"journey_map_id":m,"stage_operations":[{"action":"rename","key":k,"label":"Alpha only label"}]})
st2,_,_=shape(); a2=[s for s in st2 if s["key"]==k][0]
chk("a rename that leaves stage_goal out keeps the goal", a2["label"]=="Alpha only label" and a2.get("stage_goal")=="Done when tested", f"label={a2['label']} goal={a2.get('stage_goal')} {b.get('_err','')}{b2.get('_err','')}")
c=mcp("scaffold_map",{"journey_map_id":m,"stage_operations":[{"action":"remove","key":k},{"action":"remove","key":"nope"}]})
st3,ln3,cells3=shape()
chk("remove deletes the stage AND its cells, and reports an unknown key", all(s["key"]!=k for s in st3) and cells3==len(st3)*len(ln3) and any(e.get("key")=="nope" for e in (c.get("errors") or [])), f"cells={cells3} expected={len(st3)*len(ln3)} errors={len(c.get('errors') or [])} {c.get('_err','')}")
d=mcp("scaffold_map",{"journey_map_id":99999999,"stage_operations":[{"action":"add","label":"x"}]})
chk("another account's / missing map is refused", "_err" in d, str(d)[:80])
print(f"{sum(res)}/{len(res)} passed"); sys.exit(0 if all(res) else 1)
