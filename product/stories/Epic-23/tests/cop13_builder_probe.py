"""COP-13 part A - Journey Map Builder before/after the model move: three REAL fill phases (description,
customer, internal) through ai_message builder_mode, on a fresh fixture map made through the MCP door.
Test admin usr2-q, account 13. Never prints a token.
Usage: python cop13_builder_probe.py - <label>      (makes its own "(safe to delete)" map)
Pass = what the Builder prompt promises: each phase answers in one short sentence; description cells get text
(batch_update); customer and internal cells get actor fields with ONLY the allowed keys (update_actor_cell_fields);
no scaffold or structure change; nothing written to the wrong lens; confirmed/locked cells untouched.
"""
import sys, time
sys.stdout.reconfigure(encoding="utf-8", errors="replace")
from cop13_builder_lib import *
T = token(sys.argv); label = sys.argv[2] if len(sys.argv) > 2 else "run"
PROMPTS = {
 "description": "[BUILD_PHASE:description] Fill the Description lens ONLY across all stages. Use batch_update only. DO NOT call update_actor_cell_fields. DO NOT touch any other lens.",
 "customer": "[BUILD_PHASE:customer] Fill Customer actor lenses ONLY (actor_type=customer) across all stages. Use update_actor_cell_fields only. DO NOT call batch_update. DO NOT touch non-customer lenses.",
 "internal": "[BUILD_PHASE:internal] Fill Internal actor lenses ONLY (actor_type=internal) across all stages. Use update_actor_cell_fields only. DO NOT call batch_update. DO NOT touch non-internal lenses.",
}
ALLOWED = {
 "customer": {"entry_trigger","emotions","information_needs","decisions_required","friction_points","assumptions","acceptance_criteria","expected_output","channel_touchpoint"},
 "internal": {"task_objective","entry_trigger","tools_systems","information_needs","decisions_required","friction_points","assumptions","handoff_dependencies","success_criteria","output_deliverable","employee_constraints","pain_points"},
}
M, r = make_map(T, f"COP-13 builder probe {label} (safe to delete)")
print(f"[{label}] map {M} made: {r.get('cells_created')} cells")
g0 = state(T, M); stages0 = len(g0["stages"]); lens0 = len(g0["lenses"])
conv = 0; t_all = time.time()
for phase, prompt in PROMPTS.items():
    t0 = time.time()
    c, b = retry_req("POST", JM + f"/journey_map/{M}/ai_message", {"conversation_id": conv, "content": prompt, "builder_mode": True, "mode": "interview"}, T, to=900)
    conv = b.get("conversation_id", conv) if isinstance(b, dict) else conv
    reply = b.get("reply") if isinstance(b, dict) else None
    if not reply and isinstance(b, dict):
        msgs = b.get("messages") or []
        reply = str(msgs[-1])[:300] if msgs else str(b)[:300]
    print(f"  {phase}: ({time.time()-t0:.0f}s, {c}) {str(reply)[:240]!r}")
    check(f"{phase}: the phase answered", c == 200)
g = state(T, M)
cells = g["cells"]
def row(key): return [x for x in cells if x["lens_key"] == key]
desc = row("description"); cust = row("lens-2"); intl = row("lens-3")
filled = lambda cs, f: sum(1 for x in cs if f(x))
d_ok = filled(desc, lambda x: bool((x.get("content") or "").strip()))
real = lambda x: any(str(v).strip() for v in (x.get("actor_fields") or {}).values())
c_ok = filled(cust, real)
i_ok = filled(intl, real)
print(f"  filled: description {d_ok}/{len(desc)}, customer {c_ok}/{len(cust)}, internal {i_ok}/{len(intl)}  ({time.time()-t_all:.0f}s total)")
check("description row filled with text (most cells)", d_ok >= len(desc) * 0.8, f"{d_ok}/{len(desc)}")
check("customer row filled with actor fields (most cells)", c_ok >= len(cust) * 0.8, f"{c_ok}/{len(cust)}")
check("internal row filled with actor fields (most cells)", i_ok >= len(intl) * 0.8, f"{i_ok}/{len(intl)}")
bad = {k: sorted(set(x["actor_fields"]) - ALLOWED[k]) for k, cs in (("customer", cust), ("internal", intl)) for x in cs if x.get("actor_fields") and set(x["actor_fields"]) - ALLOWED[k]}
check("only allowed field keys were used", not bad, short(bad, 200))
check("actor cells left no text in 'content' (right tool for the right lens)", all(not (x.get("content") or "").strip() for x in cust + intl), "")
check("description cells carry no actor fields (right tool for the right lens)", all(not real(x) for x in desc), "")
check("the structure was not changed", len(g["stages"]) == stages0 and len(g["lenses"]) == lens0, f"{len(g['stages'])}/{stages0} {len(g['lenses'])}/{lens0}")
print("map id:", M, " conversation:", conv)
done()
