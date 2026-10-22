# Epic-8 — API access control, then map ordering

Started 2026-10-18. Both epics come out of one discovery: the founder asked for
the ability to **insert and resequence a column or a row** in a journey map. The
discovery found that the two columns ordering depends on (`display_order`, `key`)
can be rewritten by anyone on the internet with no login.

So the ordering feature is blocked on closing the API, not on the ordering work
itself.

## Epics

| Epic | What it enables | Status |
|---|---|---|
| [SEC-1 — API access control](EPIC-SEC-1-api-access-control.md) | Every journey-map endpoint requires a login and proves ownership | **01–05 done** · 06 partly · 07 to-do — group went from **28 open endpoints to 0** |
| ORD-1 — Insert and resequence (not yet written) | Insert a column/row at a position; move it left/right or up/down | Blocked on SEC-1 |

## Why in this order

- SEC-1 produces the **ownership guard** that ORD-1's new endpoints call.
- Without it, ORD-1's governance section would promise an ordering rule the API
  does not enforce — the rule is bypassable in one `curl`.
- Fixing auth after shipping ordering means writing the same endpoints twice.

## The discovery behind it (2026-10-18)

Recorded here so it is not re-derived:

- `journey_stage` / `journey_lens` already carry `display_order`. Add is
  append-only (`max(display_order) + 1`); remove leaves a gap and nothing
  renumbers.
- A reorder **already exists** but only inside `ai/tool/mutate_structure`
  (`reorder_stages` / `reorder_lenses`) — unreachable from the UI.
- `functions/planner/resequence.xs` + `POST timeline/{id}/reorder` are the
  correct precedent to copy: exact-permutation check, one transaction, patch
  each row by its own id.
- **Keys must never be renumbered.** `journey_stage.key` is documented as stable
  (PRD §320); `primary_actor_lens` is a *text key*, not a foreign key; and
  `work_task`'s identity is `(work_item_id, stage_key, lens_key)`. Today keys
  are minted as `s{max_display_order + 1}`, which collides the moment anything
  normalises `display_order` to 1..n. ORD-1 must change key minting first.
- **In-flight jobs are safe** from a live reorder: `work_task` has no order
  column and reads its order from the job's *pinned* version snapshot.
- Live scan (complete: 200 stages, 198 lenses, 24 maps): **zero duplicate keys,
  zero duplicate display_order**. 3 maps have gapped stage order, 13 have gapped
  lens order — so resequence must accept gapped input.

## Found along the way, not in scope here

- **Orphan structure rows.** Stages and lenses reference 30 distinct
  `journey_map` ids, but only 24 maps exist — 6 deleted maps left their columns
  and rows behind. DEL-1 territory; flagged, not fixed.
- `scratch/ord1_branch_probe` (function 174, workspace 1) — a throwaway written
  during discovery to test a loop shape. Safe to delete.
- **Five test users in five separate accounts already existed** (users 6–10,
  accounts 3–7), each left behind by AUTH-1, GOV-1, DEL-1 and PLN-9. SEC-1's
  story-03 notes claimed there were none and asked the founder to create some;
  that was wrong and is corrected in the epic. They are what story 04 was
  verified with, so the founder's own login was never used for testing.
