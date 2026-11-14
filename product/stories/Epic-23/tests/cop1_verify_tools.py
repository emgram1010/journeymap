"""Compare what is LIVE (a saved listTools result with xanoscript) against what was meant to be
pushed (push_tools/<name>.xs). Trailing whitespace on a line is ignored; everything else must
match. Prints one line per tool and a diff summary for any mismatch.
Usage: python verify_tools.py <path to saved listTools result>
"""
import difflib, json, os, sys

SP = os.path.dirname(os.path.abspath(__file__))


def norm(s):
    return [l.rstrip() for l in s.replace("\r\n", "\n").strip().split("\n")]


d = json.loads(open(sys.argv[1], encoding="utf-8").read())
live = {}
for it in d["items"]:
    x = it.get("xanoscript") or {}
    live[it["name"]] = x.get("value") if isinstance(x, dict) else x
man = json.load(open(f"{SP}/push_tools/_manifest.json"))
bad = 0
for t in man:
    want = norm(open(f"{SP}/push_tools/{t['name']}.xs", encoding="utf-8").read())
    got = norm(live.get(t["name"]) or "")
    if want == got:
        print(f"MATCH     {t['name']}")
        continue
    bad += 1
    diff = [l for l in difflib.unified_diff(want, got, "intended", "live", lineterm="", n=0)
            if l[:1] in "+-" and l[:3] not in ("+++", "---")]
    gated = any("journey/tool_gate" in l for l in got)
    print(f"MISMATCH  {t['name']}: {len(diff)} differing lines; gate present live: {gated}")
    for l in diff[:8]:
        print("     ", l[:150])
print(f"{len(man) - bad}/{len(man)} match")
sys.exit(1 if bad else 0)
