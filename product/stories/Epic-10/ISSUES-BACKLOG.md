# Issues found while building ORD-1 — prioritized

Logged 2026-10-19 while building insert-on-the-seam and resequencing (Epic-10,
ORD-1). **Highest priority first.** Each item says what is wrong, how it shows
up for a user, and the cheapest fix. Nothing here blocks the feature that
shipped — it all predates it or sits next to it.

| # | Priority | Issue | Who notices | Effort |
|---|---|---|---|---|
| 1 | 🔴 High | AI tools call an **empty endpoint** for 5 structure actions | AI chat says "done" but nothing happens | M |
| 2 | 🔴 High | `scaffold_map` "add" **crashes** when the AI omits an optional field | AI build fails mid-way | S |
| 3 | 🔴 High | SEC-1 is unfinished: **no CI guard**, 69 endpoints with unproven ownership | Nobody, until a leak | M |
| 4 | 🟡 Medium | **No automated UI test** for the seam/arrows; 26 Playwright specs already failing | Regressions go unseen | S–M |
| 5 | 🟡 Medium | **Nobody is a platform admin** — Health page and 3 tools unreachable | Founder | XS (a decision) |
| 6 | 🟡 Medium | Add/insert/reorder ignore **archived** maps | User edits an archived map | S |
| 7 | 🟡 Medium | Older endpoints use `owner_user`, not account — **teammates can't add columns** | Teams | S |
| 8 | 🟡 Medium | Same role prompt copied 4×, **already drifted** (metrics prompt differs) | Inconsistent AI output by entry point | M |
| 9 | 🟢 Low | Orphan stages/lenses from 6 deleted maps | Nobody (invisible since SEC-1) | S |
| 10 | 🟢 Low | Removing a column leaves a gap in `display_order` | Nobody (next reorder closes it) | XS |
| 11 | 🟢 Low | `listJourneyCells()` fallback has always returned 400 | Only if the bundle path fails | XS |
| 12 | 🟢 Low | Local `.xs` files drift from live | The next AI session | S |
| 13 | 🟢 Low | Seam/arrow polish: no keyboard shortcuts, no drag, narrow columns | Power users | M |
| 14 | 🟢 Low | `planner/resolve_actor` is misnamed (generic, used by 15 journey-map endpoints) | Developers | S |
| 15 | 🟡 Medium | A removed column/row's **key can be re-minted** for the next one added | Anyone reading an old published version | M |
| ~~16~~ | ✅ Fixed | ~~Anyone logged in can delete a column or row from any map~~ — **fixed 2026-10-21**, account-scoped | — | — |
| 17 | 🟡 Medium | The Day Board **opens on a date outside the plan's own window**, showing an empty lane with no hint | Anyone opening a plan — cost a real hour on 2026-10-20 | S |
| 18 | 🟡 Medium | `work_item.attributes` is **free-form JSON**, so quantities never aggregate across jobs | Anyone asking "how many did we process last month" | M |
| 19 | 🟡 Medium | **Child jobs are impossible** — `parent_work_item_id` is hardcoded to 0 on create | The damaged-items-go-to-repair flow | M |
| 20 | 🟢 Low | Test junk in the founder's live account: 12 test plan templates, 2 links to a deleted map | The founder, every time they open Templates | XS |

Fixed along the way (not open): see the bottom of this file.

**✅ Closed by [ORD-2](EPIC-ORD-2-ai-structure-parity.md) (2026-10-19):**
**#1** (AI tools calling an empty endpoint), **#8** (actor templates copied and
drifted) and **#10** (remove leaves a gap). ORD-2 also fixed two bugs nobody had
recorded — see its Build results — and found one new issue, **#15** below.

---

## 🔴 1. AI tools call an empty endpoint for five structure actions

**What:** `ai/tool/mutate_structure` (`add_stage`, `remove_stage`,
`remove_lens`) and `ai/tool/scaffold_structure` (stage add, stage remove, lens
remove) do `api.call "" verb=GET { api_group = "" }` — an empty path in an empty
group. Confirmed in the **live** tool source, not just the local files.

**How it shows up:** the AI says it added or removed a column, and either errors
or does nothing. `scaffold_map` (the other structure tool) does these with direct
database writes and works.

**Fix:** replace each `api.call ""` with the same direct writes `scaffold_map`
uses: `journey/next_stage_key` + `db.add` + cell scaffolding for add; query cells,
then `db.del` each by id, inside `db.transaction`, for remove. Or have the AI use
`scaffold_map` only, and remove these actions from the two tools' instructions so
the AI stops choosing them.

**Covered by:** ORD-2 story 05 — which takes neither of those options. It puts
the logic in shared functions that the endpoints and the tools both call, so the
AI and the buttons cannot drift apart. ORD-2 also flags that these six sites sit
inside the `conditional`-in-`foreach` shape that silently discards writes, so
fixing the empty call may expose a second bug rather than fix one.

## 🔴 2. `scaffold_map` "add" crashes when the AI omits `stage_goal`

**What:** stage "add" reads `$op.stage_goal` and `$op.primary_actor_lens`
directly. When the AI leaves them out — the tool's own instructions call them
optional — it fails with `Unable to locate var: op.stage_goal`. Reproduced live
on 2026-10-19; it worked once both fields were sent as `""`.

**Fix:** read them with a default: `$op|get:"stage_goal":""` (literal key, so the
default works — CLAUDE.md). Two lines.

## 🔴 3. SEC-1 is unfinished

- **Story 07 (CI guard)** isn't built. Nothing stops the next endpoint shipping
  with `auth = false`. ORD-1 added two endpoints and both are correct, but by
  care, not by a check.
- **Story 06:** 69 of 82 journey-map endpoints have no *proven* ownership check.
  All of them require a login.
- Details: `product/stories/Epic-8/EPIC-SEC-1-api-access-control.md`, "Still open".

## 🟡 4. No automated UI test for the seam and arrows

**What:** the seam `+`, the arrows and the refusal path were verified by hand in
a real browser (test user 9, test map 210 — see the epic). Pure logic and markup
are covered by 17 new unit tests. There is **no Playwright spec**, because the
26 existing specs already fail at sign-in (no `E2E_AUTH_TOKEN`), so a new one
would fail for the same reason.

**Fix:** mint `E2E_AUTH_TOKEN` in Playwright global setup using the magic-link
flow (`generate_magic_link` → `reset/magic-link-login`), the way this session
did. That revives the existing 26 specs too. Then add `e2e/matrix-order.spec.ts`.

## 🟡 5. Nobody is a platform admin

`is_platform_admin` is `false` for all 9 users, so the Health page and the three
maintenance tools (dedupe scan/apply, backfill) are unreachable by everyone,
including the founder. Raised three times. **Decision:** set it on user 2, or
record "locked by design".

## 🟡 6. Archived maps can still be restructured

`journey_stage/add`, `journey_lens/add` and the two new reorder endpoints don't
call `guards/assert_not_archived`. The guard exists and the planner uses it.
**Fix:** one `function.run` in each, after the ownership check.

## 🟡 7. Older endpoints check `owner_user`, not account

`journey_stage/add`, `journey_lens/add`, remove, rename and publish check
`owner_user == $auth.id`. The new reorder endpoints check the **account**
(SEC-1's rule). Result: a teammate in the same account can reorder a map but
cannot add a column to it. SEC-1 deliberately left this alone because it changes
behaviour. **Fix:** switch them to `journey/assert_map_owner`. Decide first
whether teammates *should* edit each other's maps.

## 🟡 8. Role prompts and actor-field scaffolds are copied four times — and have drifted

The same per-actor-type role prompts and `actor_fields` scaffolds (~150–300
lines) are copied in `journey_lens/add`, `journey_stage/add`,
`mutate_structure` and `scaffold_structure`. **They already disagree:** the
metrics prompt in `scaffold_structure` differs from the one in `journey_lens/add`,
and `mutate_structure` has no financial or metrics template. So a row's AI
behaviour depends on which path created it.
**Fix:** one `journey/actor_template` function returning
`{template_key, role_prompt, actor_fields}` per actor type, called from all four.

**Covered by:** ORD-2 story 01. Note it is **not** a pure refactor — the copies
disagree, so extracting one picks a winner per actor type. That choice gets
written down before anything is replaced.

## 🟢 9. Orphan structure rows

Stages and lenses still reference 6 deleted maps. Invisible since SEC-1 (no
caller can read them), but still stored. DEL-1 territory.

## 🟢 10. Remove leaves a gap

Removing a column or row doesn't renumber the rest. Harmless: every reorder and
insert now renumbers to 1..n. If wanted, call `journey/apply_*_order` at the end
of the remove endpoints.

**Covered by:** ORD-2 story 03, free — the shared remove function ends with that
call anyway.

## 🟢 11. `listJourneyCells()` fallback returns 400

`GET /journey_cell` requires `journey_map` (min 1) but the frontend fallback
sends none. Pre-existing since RES-4. Only matters if the main bundle load fails.

## 🟢 12. Local `.xs` files drift from live

`ai/tool/scaffold_map.xs` predated RES-6-01's transactions (fixed this session).
Others likely drift the same way. **Fix:** a one-off sweep comparing each local
file to `getAPI`/`getFunction`/`getTool`.

## 🟢 13. Seam and arrow polish

- No keyboard shortcuts (Alt+←/→ to move).
- Drag-and-drop deferred by decision.
- On a very narrow column the bottom-left `+` and the bottom-right arrows sit
  close together.
- The version badge updates 5 seconds after a move (existing debounce), not
  instantly.

## 🟢 14. `planner/resolve_actor` is misnamed

Generic (user → account + role), now called by 15 journey-map endpoints.
Renaming touches 19 planner endpoints; do it with the next planner change.

---

## Fixed along the way (closed)

- **`scaffold_map` minted keys from `count + 1`** — re-minted an existing key
  after any remove. Fixed by ORD-1 story 01.
- **Error banners showed the raw server reply** (`Xano POST /x failed (400):
  {"code":…}`) for **every** action in the map editor. The client already
  extracted the server's friendly sentence (`serverMessage`) but `App.tsx` never
  used it. Fixed in `getErrorMessage`; verified in the browser.
- **The AI's `reorder_stages` / `reorder_lenses` probably never wrote anything.**
  It decided whether to write by testing a var updated earlier in the same loop
  iteration — the CLAUDE.md pattern where every write in the branch is silently
  discarded. Replaced with the shared `journey/apply_*_order` (story 06).
- **A unique index on `(journey_map, key)` turned out to be unnecessary.**
  The existing unique index on `(journey_map, key, display_order)` already
  rejects two simultaneous adds (proven: "Duplicate record detected"), because a
  race computes the same key *and* the same order.

## 🟡 15. A removed key can be handed to a different row later

**What:** stage and lens keys are minted as
`max(shape-valid key suffixes, display_orders) + 1` over the map's **live**
rows. A removed row's key is therefore free to be issued again. Seen live on
2026-10-19: a row keyed `lens-2` was removed, and the very next row created
took `lens-2`.

**Why it matters:** `key` is identity, not a label. A published
`journey_map_version` snapshot, and `work_task` identity
`(work_item_id, stage_key, lens_key)`, both refer to rows by key. A snapshot
pinned to the old `lens-2` now resolves to a different actor — silently, and
looking entirely plausible.

**What already protects you:** ORD-2's E-ORD-005 refuses removing a key that a
task in a published plan points at. So the case with live work attached is
blocked. The exposed case is a published version with **no** tasks against it.

**Fix:** mint from a per-map monotonic counter (a `next_key_no` on
`journey_map`, or the max taken across live rows **and** every version
snapshot). This changes the mint ORD-1 shipped, so it wants its own story and
its own test pass — not a patch.

## ✅ 16. Anyone logged in can delete a column or row from any map — FIXED

**What:** `journey_stage/remove/{id}` (endpoint 48) and
`journey_lens/remove/{id}` (endpoint 50) check only that the row exists. There
is no ownership check of any kind. Confirmed by reading the **live** source on
2026-10-20, during ORD-2.

**How it shows up:** it does not, until it does. Any authenticated user of any
account can delete a column, and its cells, from any map in the workspace.
ORD-2 deliberately left this unchanged rather than alter behaviour inside a
refactor, and recorded it here instead.

**Not tested, on purpose.** The only way to prove it is to delete something of
the founder's.

**Fixed 2026-10-21.** Both endpoints now load the row, then call
`journey/assert_map_owner` — the same guard the reorder endpoints use.

**Account-scoped, not owner-scoped**, matching those endpoints and SEC-1's
rule: a teammate in the same account may remove a column. That also closes the
inconsistency in #7, where a teammate could already reorder a map they could
not add to. The founder was asleep and had said to proceed on recommendation;
this was the recommendation, and it is a one-line change to reverse.

**Proved live:** deleting a stage and a lens from **another test account's**
map is refused 403 `E-GOV-001` with the row still present; the same call on the
caller's own map succeeds and cascades; no token is 401. The refusal test
deliberately targeted another test account rather than map 178, so a failing
guard could not have damaged real work.

## 🟡 17. The Day Board opens on a date outside the plan's own window

**What:** plan "tesy" has a planning window of 20 Oct – 2 Nov. The Day Board
opened on **13 Oct** — before the window starts — because an earlier timeline
existed on that date. The agent's lane was genuinely empty, and nothing on
screen said the date was outside the plan, or that work existed on another day.

**How it shows up:** exactly as "the feature is broken". On 2026-10-20 the
founder scheduled 8 steps correctly, then reported seeing no tasks. Everything
was right; the board was simply parked a week early. The Schedule view showed
the work immediately.

**Fix:** open the Day Board on the first date **inside** the planning window
that has work, and mark an out-of-window date on screen. The board endpoint
already computes an `oow` flag per timeline — it is just not used to choose the
opening date.

## 🟡 18. Job quantities are free-form, so they never add up

**What:** `work_item.attributes` is an open `json` column. A job can carry
`{chairs: 25, tables: 3}`, and the next one `{Chairs: 40}` or
`{chair_count: 40}`. Nothing constrains the keys and nothing reports on them.

**How it shows up:** the moment anyone asks "how many items did we turn around
last month". The data is all there and cannot be summed.

**Fix:** depends on how far you want to go. Smallest: a declared list of
quantity keys per map, validated on job creation. Largest: this is really the
same need as [CAP-1](../Epic-12/EPIC-CAP-1-capture-fields.md) — a declared,
typed field set — applied to the job rather than the step. Worth deciding
together with CAP-1 rather than separately.

## 🟡 19. Child jobs are impossible

**What:** `work_item.parent_work_item_id` exists on the table, but
`apis/planner/554_work_item_POST.xs` writes `parent_work_item_id: 0`
unconditionally. Nothing can ever set it.

**How it shows up:** the flow the founder described — 3 damaged tables leaving
the main process for a repair map — cannot be built. It is the concrete form of
"structure follows divergence, not count", and today the divergence has nowhere
to go.

**Fix:** accept an optional parent on create, and add the action that produces
one: "split these items out of this job". Both ORD-2's and BLK-1's **Still
open** sections name this as the natural next epic.

## 🟢 20. Test junk in the founder's live account

**What:** account 2 holds 15 plan templates, 12 of them active, of which 8 are
named `E2E roster 17922…` plus `PLAN-3 smoke template`, `GAP-1 duplicate-name
repro` and `guard check 1792296041`. The only real one, `Quote Handling
Template`, is switched off and therefore hidden. Both of the account's only two
template→map links point at **map 205, which no longer exists**.

**How it shows up:** the Templates screen is mostly noise, and the one real
template is invisible.

**Fix:** delete the test templates and the two dangling links. Needs the
founder's say-so — they are rows in their live account, not scratch data.

---

## Found while building BLK-1 (2026-10-21), fixed in the same change

- **`planner/unschedule_work_task` deleted one link and then the whole slot.**
  Correct while a slot held one step; the moment a slot holds a card it would
  have deleted the slot and left its other links behind, pointing at nothing.
  Those steps would have been invisible to the backlog forever — "unscheduled"
  means "absent from that link table", and there would have been no slot left
  to unschedule them from. Permanently stuck, nothing logged, no error. Found
  by reading the function before building on it.
- **Endpoint 576's refusals only looked at the named step.** A card could have
  been dissolved out from under a sibling step that had already been started.
  Both checks now cover every step the slot holds.
