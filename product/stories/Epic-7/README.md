# Epic-7 — Build guards and working practice

Started 2026-10-18, from a founder question rather than a feature request:

> *"What do we need to do so you improve both your architecting / planning / mitigating plan to avoid these bugs?"*

Five bugs were introduced and caught inside a single session. Every one passed typecheck, passed the suite, and pushed cleanly. They were found by grepping by hand or by opening a browser — neither of which is a process.

## Epics

| Epic | What it enables | Status |
|---|---|---|
| [GUARD-1 — Build Guards](EPIC-GUARD-1-build-guards.md) | The recurring classes of bug fail the build instead of being remembered | **01, 02, 03 done** · 04, 05 to-do |

## The diagnosis, in one line

**Work was verified at the layer that changed, not at the layer the user touches** — and the worst bugs were *silent*: plausible wrong answers that no code review would catch.

## What is a guard here

A guard earns its place by pointing at a **specific bug that already got through**. Not linting. Each one:

- fails the build, rather than warning
- says **what breaks**, not just that a rule was violated
- carries its exceptions **named in code with a reason**, so escaping it is a decision someone recorded

## Related, not in this epic

- `product/ai-learnings.md` — the working lessons behind these guards, kept as prose.
- `CLAUDE.md` — the XanoScript gotchas. Several of this session's bugs were already documented there and still made; a guard beats a note.
- **Proposed, not yet agreed:** a step in CLAUDE.md's build protocol that says *look at it in a browser before calling it done*. That step is what actually found three of this session's bugs, and the protocol today is entirely backend-shaped.
