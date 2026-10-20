# Epic-10 — Insert and resequence a column or a row

Created 2026-10-19. This is the feature the founder originally asked for:
**insert and resequence a column (stage) or a row (lens) in a journey map.**

The discovery that produced it lives in `product/stories/Epic-8/README.md`,
because scoping this feature is what uncovered the open-API problem that became
SEC-1. Epic-8 holds the security work; **Epic-10 holds the ordering work.**

## Epics

| Epic | What it enables | Status |
|---|---|---|
| [ORD-1 — Insert and resequence](EPIC-ORD-1-insert-and-resequence.md) | Insert a column/row at a position; move it left/right or up/down, from the matrix | ✅ **All 6 stories done (2026-10-19)** — seam insert + move arrows live for columns and rows |
| [ORD-2 — The AI reshapes a map the same way the buttons do](EPIC-ORD-2-ai-structure-parity.md) | Gives the AI agent add / remove / place-at-a-position, through the same functions the buttons use. Fixes six AI actions that report success and do nothing | 📋 **Not started** — 7 stories, depends on ORD-1 (done) |

## ORD-1 build order

Story 01 is not negotiable as the first story. Everything else can move.

| # | Story | Effort | Model |
|---|---|---|---|
| 01 | Key minting off `display_order` | **S** | Opus 5.5 |
| 02 | `jm/resequence_stages` / `jm/resequence_lenses` | **M** | Opus 5.5, then a review pass |
| 03 | `POST .../reorder/{map_id}`, owner-guarded, exact-permutation | **M** | Sonnet 5.5 |
| 04 | Insert-at-position (`after_stage_id` / `after_lens_id`) | **M** | Sonnet 5.5 |
| 05 | Seam `+` to insert; arrows to move left/right, up/down | **L** | Sonnet 5.5 |
| 06 | Repoint `ai/tool/mutate_structure`; governance; tests | **S–M** | Sonnet 5.5 |

**Total: roughly 2–3 working sessions.** Story 05 is the biggest single chunk —
it is the only one that touches React, and the seam affordance has to be built
inside Tabulator's header markup rather than as JSX.

## ORD-2 build order

The order is not negotiable: **04 before 05.** The buttons must be proved
unbroken on the shared functions *before* any new capability is added, so a
regression shows up while the change set is still small.

| # | Story | Effort | Model |
|---|---|---|---|
| 01 | One actor template, not four copies | **S–M** | Sonnet 5.5 |
| 02 | One place adds a column or a row | **M** | Opus 5 — it absorbs the insert logic |
| 03 | One place removes a column or a row | **M** | Opus 5 — cascade delete is the riskiest code |
| 04 | The buttons keep working, provably | **S** | Sonnet 5.5, Opus 5 if anything regresses |
| 05 | The AI's six dead actions actually work | **M** | Opus 5 — a second silent-failure bug may be underneath |
| 06 | The AI can place, not just append | **S** | Sonnet 5.5 |
| 07 | The AI knows what it can do (prompts) | **S** | Haiku 5.5 would do, Sonnet 5.5 is safer |

**Total: roughly 1–2 working sessions.** Most of it moves proven code behind a
function boundary rather than inventing logic. Stories 02, 03 and 05 are the
ones that earn Opus: a cascade delete that half-applies and a conditional that
silently discards its writes are both failure modes this codebase has already
been bitten by.

**Why ORD-2 exists at all:** the AI agent (`Journey Map Assistant`, agent 18)
reaches structure through `mutate_structure` and `scaffold_structure`, and six of
their call sites point at an empty endpoint. The agent says it added the column;
nothing happened. ORD-1 fixed the agent's *reorder* on the way past — ORD-2
finishes the job.

## How insert is triggered

**A `+` on the seam**, the way a Confluence table does it: hover the line between
two columns and a `+` appears; clicking it inserts a column between those two.
Same on the line between two rows. Decided 2026-10-19.

This needs **no extra backend work** — the seam between A and B is exactly
`after_stage_id = A`, which story 04 already specifies, and the leading seam is
`after_stage_id = 0`, which it also already covers. N columns give N+1 seams, so
"insert before" and "insert after" collapse into one unambiguous affordance per
boundary.

**Moving stays on arrows.** Confluence moves columns by dragging; drag-and-drop
is deferred, so left/right and up/down arrows live in the header alongside the
existing edit button.

## Why story 01 is first

Keys are minted from `display_order` in **three** places. Resequence normalises
`display_order` to 1..n. The next add after a normalise therefore mints a key
that already exists — and `key` is identity, not a label: `primary_actor_lens`
holds a *text lens key*, and `work_task` identity is
`(work_item_id, stage_key, lens_key)`.

Shipping any ordering feature before story 01 would corrupt live execution
records. Full detail in the epic.

## Is it unblocked?

**Yes.** ORD-1 was blocked on SEC-1 producing an ownership guard that the new
reorder endpoints could call. That guard exists and is proven:

- `journey/assert_map_owner` (function 178) — delegates to `guards/assert_owns`,
  emits `E-GOV-001`, logs the refusal through `ops/log_event`.
- The journey-map API group went from **28 open endpoints to 0**.

## SEC-1 — recommended action

SEC-1 is at **stories 01–05 done · 06 partly · 07 to-do**. Two pieces remain.
The recommendation is to **start ORD-1 now** and fold the SEC-1 remainder in as
described below, rather than finishing SEC-1 first.

| SEC-1 remainder | Recommendation | Why |
|---|---|---|
| **Story 07 — the CI build guard** (fails the build if a journey-map endpoint has `auth = false` without a named exception) | **Do it as the first task of ORD-1**, before story 01 | It protects against *future* open endpoints, not current exposure — there are none. ORD-1 adds **two brand-new endpoints**, which is precisely when a guard that catches a forgotten `auth` line earns its cost. Doing it now also means the guard is in place before story 05 starts pushing UI pressure to ship fast. Cost: small, mechanical, no decisions |
| **Story 06 — 69 of 82 endpoints still unswept** | **Leave it. Do not block ORD-1 on it** | The 13 endpoints the app actually uses are swept and proved over real HTTP with two accounts' tokens. The remaining 69 are not *open* — all 82 now require a login. What they lack is a **proven ownership check**, and many use the older `owner_user` precondition that SEC-1 deliberately left alone because tightening it is a behaviour change, not a security fix. Sweeping them is a day of careful, low-yield work with a real regression risk, and none of it is on ORD-1's path |
| **`is_platform_admin` is `false` on all nine users** | **Answer it, separately from both epics** | Nobody can run the three maintenance tools and the Health page is unreachable by its only intended reader. One row patched either way. It blocks nothing, but it has now been raised three times |
| **Four test leftovers awaiting delete permission** | **Answer it** — scratch functions 174/179/180 and junk map 209 in test account 6 | Housekeeping. Nothing reachable by the app. ORD-1 will create more scratch functions, so a standing answer is worth more than four individual ones |

**In one line:** do story 07 first because ORD-1 adds endpoints; skip the rest of
story 06 because nothing is open any more and the unswept 69 are a behaviour
decision, not a hole.

## Relationship to Epic-8

Epic-8's README still lists ORD-1 as "not yet written" and living there. That row
is now stale — the epic was written here instead, at the founder's request.
**Not edited**, per CLAUDE.md (do not edit documents that were not part of the
request); flagged here so the two folders can be reconciled on request.

## Issues found along the way

Ranked highest to lowest in [ISSUES-BACKLOG.md](ISSUES-BACKLOG.md). The top three
are AI-tool bugs and the unfinished SEC-1 work, none of which block the feature.
