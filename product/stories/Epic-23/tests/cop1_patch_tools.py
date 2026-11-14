"""COP-1 step 2: add the run-ticket input and the gate call to every AI tool.

Reads the exact LIVE source of each tool (live_tools/<name>.xs), writes the patched source to
push_tools/<name>.xs (what gets pushed), and applies the same patch to the repo copy
ai/tool/<name>.xs (which may differ from live in other ways - those differences are kept).
Idempotent: a file that already has the gate is left alone.
"""
import json, os, re, sys

SP = os.path.dirname(os.path.abspath(__file__))
REPO = "C:/Users/javie/OneDrive/Documents/emgram1010"
SKIP = {"search_xano_docs"}  # no tenant data, used by the public demo agent

WRITE = {
    "batch_set_status", "batch_update", "build_journey_map", "clone_scenario", "create_journey_map",
    "create_workspace", "export_workflow_output", "fill_cells", "invoke_map", "link_map",
    "mutate_structure", "publish_map", "save_workflow_state", "scaffold_map", "scaffold_structure",
    "set_cell_status", "update_actor_cell_fields", "update_actor_identity", "update_cell",
    "update_journey_settings", "update_stage_contract",
}
# which input(s) name the map(s) a tool touches; [] = no single target map
MAPS = {
    "clone_scenario": ["source_map_id"],
    "compare_scenarios": ["map_a_id", "map_b_id"],
    "link_map": ["source_map_id", "target_map_id"],
    "invoke_map": ["target_map_id"],
    "create_journey_map": ["parent_map_id"],
    "create_workspace": [], "list_maps": [], "search_maps": [], "list_scenarios": [], "web_search": [],
}

TICKET_INPUT = '''    text ticket? filters=trim {
      description = "COP-1 run ticket from your context. If you were given one, pass it on every tool call exactly as given. Otherwise leave it empty."
    }
'''


def gate_block(name, maps):
    kind = "write" if name in WRITE else "read"
    out = ["    // COP-1: who is calling, and is this map theirs? Reports only until usr/tool_gate_mode says enforce."]
    targets = maps if maps else [None]
    for i, m in enumerate(targets):
        ref = f"$input.{m}" if m else "0"
        var = "$cop1_gate" if i == 0 else f"$cop1_gate_{i + 1}"
        out += [
            '    function.run "journey/tool_gate" {',
            f'      input = {{journey_map_id: {ref}, ticket: $input.ticket, tool: "{name}", kind: "{kind}"}}',
            f"    }} as {var}",
            "",
        ]
    return "\n".join(out) + "\n"


def patch(name, src):
    if "journey/tool_gate" in src:
        return src, "already"
    lines = src.replace("\r\n", "\n").split("\n")
    maps = MAPS.get(name, ["journey_map_id"])
    # --- input block (2-space indent, top level of the tool) ---
    i_in = next((i for i, l in enumerate(lines) if re.match(r"^  input \{\s*$", l)), None)
    i_empty = next((i for i, l in enumerate(lines) if re.match(r"^  input \{\s*\}\s*$", l)), None)
    if i_in is not None:
        i_close = next(i for i in range(i_in + 1, len(lines)) if lines[i] == "  }")
        body = "\n".join(lines[i_in + 1:i_close])
        for m in maps:
            if not re.search(r"\b" + re.escape(m) + r"\b", body):
                raise SystemExit(f"{name}: expected input {m} not found")
        if re.search(r"\bticket\b", body):
            raise SystemExit(f"{name}: already has a ticket input")
        ins = TICKET_INPUT.rstrip("\n").split("\n")
        if lines[i_close - 1].strip() != "":
            ins = [""] + ins
        lines[i_close:i_close] = ins
    elif i_empty is not None:
        if maps:
            raise SystemExit(f"{name}: empty input but maps expected")
        lines[i_empty:i_empty + 1] = ["  input {"] + TICKET_INPUT.rstrip("\n").split("\n") + ["  }"]
    else:
        raise SystemExit(f"{name}: no input block found")
    # --- stack block ---
    i_st = [i for i, l in enumerate(lines) if re.match(r"^  stack \{\s*$", l)]
    if len(i_st) != 1:
        raise SystemExit(f"{name}: expected exactly one top-level stack, found {len(i_st)}")
    lines[i_st[0] + 1:i_st[0] + 1] = gate_block(name, maps).rstrip("\n").split("\n") + [""]
    return "\n".join(lines), "patched"


def main():
    idx = json.load(open(f"{SP}/live_tools/_index.json"))
    os.makedirs(f"{SP}/push_tools", exist_ok=True)
    manifest = []
    for name in sorted(idx):
        if name in SKIP:
            continue
        live = open(f"{SP}/live_tools/{name}.xs", encoding="utf-8").read()
        new, st = patch(name, live)
        open(f"{SP}/push_tools/{name}.xs", "w", encoding="utf-8", newline="\n").write(new)
        lp = f"{REPO}/ai/tool/{name}.xs"
        loc = open(lp, encoding="utf-8").read()
        nl, st2 = patch(name, loc)
        open(lp, "w", encoding="utf-8", newline="\n").write(nl)
        manifest.append({"name": name, "tool_id": idx[name]["id"], "kind": "write" if name in WRITE else "read",
                         "maps": MAPS.get(name, ["journey_map_id"]), "lines": new.count("\n") + 1, "bytes": len(new.encode())})
        print(f"{st:8} {st2:8} {name:28} id={idx[name]['id']:<4} lines={new.count(chr(10)) + 1}")
    json.dump(manifest, open(f"{SP}/push_tools/_manifest.json", "w"), indent=1)
    print(len(manifest), "tools prepared")


if __name__ == "__main__":
    main()
