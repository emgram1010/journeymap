# SAFE-1 — Data-safety fixes

**Epic ID:** SAFE-1 (E1 in the founder's list)
**Status:** ✅ Built and verified live 2026-11-21 (stories 01, 02, 03). Two known gaps listed in Test Results; nothing committed to git yet.
**Size:** S
**Model:** **Opus 5.5** (founder, 2026-11-21: build E1 on Opus). Was Sonnet 5.5.
**Depends on:** nothing. Build first.
**Read first:** `../README.md` (findings F-1, F-2; decisions D-1, D-2).

---

## 1. Goal

**Pain:** a times-only update to a cell wiped the cell's text, and the owner could not reset a
member's password after the account was created.

**Win:** no silent loss of map content, and an admin can always get a member back in.

**Decisions (2026-11-21):** D-2 ✅ any team admin may reset. D-1 ✅ 1 hour, single use. D-8 ✅ no email. D-9 ✅ who resets whom. D-10 ✅ owner role added.

## 2. What exists today (repo files, 2026-11-21; live not compared)

| Fact | Where |
|---|---|
| `update_cell` patches with `content: $input.content ?? $cell.content`, and the same shape for four time fields | `ai/tool/update_cell.xs` lines 146–154 |
| An omitted optional text input is `""`, an omitted decimal is `0`, and `??` is strict (keeps `""` and `0`) | CLAUDE.md, verified live |
| So: times-only wipes the text; **text-only very likely zeroes the times** (finding F-1) | to prove in story 01 |
| `fill_cells` uses `$upd.content ?? $cell.content` on a JSON element, where a missing key is a real null | `ai/tool/fill_cells.xs` lines 102–107 |
| The proven way to tell omitted / null / value apart: `$raw_input\|get:"field":"__absent__"` | CLAUDE.md (STAGE-1, `update_stage_contract`) |
| Reset pieces already exist: request a reset link, sign in with a one-time link, update password | `apis/authentication/4_…`, `5_…`, `6_…` |
| Admin endpoints for a member (create, update, role, delete) with one guard, `usr/assert_team_admin` | `apis/members_accounts/18, 19, 11, 20` |
| A function that writes a hashed one-time token without sending email | `Getting Started Template/generate_magic_link` (CLAUDE.md) |

### Live check, 2026-11-21 (read-only, workspace 1, before any build)

| Tool (live id) | Live matches local? | What it really does |
|---|---|---|
| `update_cell` (3) | Yes | Confirms F-1: `$input.content ?? $cell.content` and the same for four time fields. Omitted text becomes `""`, omitted times become `0` |
| `fill_cells` (51) | Yes | 🔴 **New: it never checks `is_locked` or `status = confirmed`.** It overwrites locked and confirmed cells. Its `??` is safe for left-out keys |
| `batch_update` (5) | Yes | 🔴 **New: writes `content: $upd.content` with no fallback.** An update without a `content` key writes null and wipes the text. Skips locked and confirmed correctly |

**Other places that write cells** (story 02 must list how each behaves): AI tools
`update_actor_cell_fields`, `set_cell_status`, `batch_set_status`, `clone_scenario`,
`create_journey_map`; endpoints 42, 44 (the app's own cell save), 51 (map chat), 126, 604, 605;
functions `items/ensure_items_row`, `journey/insert_lens`, `journey/insert_stage`.

**Effect on the stories:** story 02 now also makes `fill_cells` skip locked and confirmed cells
(same rule as the other tools), and fixes `batch_update`'s missing fallback.

Note: the `mcp__xano__*` connection returned "Invalid token"; the second Xano connection worked.

## 3. Rule

**A field that was not sent is never changed. A field sent empty on purpose is cleared.**
One function holds that rule, and every tool that writes a cell calls it.

**Any team admin can start a reset for someone else, and no admin ever learns the password.**
Admins reset members; only the owner resets an admin; nobody in the account resets the owner (D-9). No email (D-8): the link is shown once to the admin.

## 4. Do not break

- Locked cells and confirmed cells are still skipped, exactly as today.
- The response shape of `update_cell` and `fill_cells` keeps every field it has today (new fields may be added).
- A person's own "forgot my password" flow is unchanged.
- `usr/assert_team_admin` is reused, not copied.

## 5. Non-goals

- Restoring text that was already wiped (story 01 only **lists** suspect cells for the founder).
- Changing how the app's own screens save a cell.
- Two-factor sign-in, password rules, single sign-on.

## 6. Stories

| File | Story |
|---|---|
| `US-SAFE-1-01-update-cell-keeps-what-was-not-sent.md` | A field that was not sent is kept (both directions) |
| `US-SAFE-1-02-one-rule-for-every-cell-writer.md` | `fill_cells` and `batch_update` use the same rule |
| `US-SAFE-1-03-owner-resets-a-member-password.md` | An admin resets a member's password (file name kept) |

## 7. Completion gate

- All tests in the three stories pass, plus `npm test` in `webapp/protype-2`, `workflow_tests/1–12` and the existing Playwright specs.
- A live smoke test on a clone (never map 178): times-only, text-only, clear-on-purpose, locked, confirmed.
- The suspect-cell list from story 01 has been shown to the founder.
- Test Results below are filled in.

## 8. Test Results

### 2026-11-21 — stories 01 and 02, part 1 (Opus 5.5)

**Pushed to workspace 1 (new, nothing calls them yet, no behaviour change):**
`journey/cell_merge_patch` (function 412) and `tests/safe1_cell_merge_cases` (function 413).

| Test | Result |
|---|---|
| `tests/safe1_cell_merge_cases`, cases c1–c8 (T-SAFE-01-1 to -6, T-SAFE-02-1, trim, actor_fields) | ✅ 8 of 8 pass, live |

**Probe facts (scratch function, deleted after):**
- `$obj|get:"k":null` returns null for a left-out key and for a key sent as null; the real value otherwise.
- **New:** `$obj|has:"k"` is **false** for a key sent as null (CLAUDE.md only covered `0`). It cannot tell "sent as null" from "left out".
- `(x ?? "__unset__") != "__unset__"` is true for `""`, `0` and objects, false only for a real null.
- `0 != "__absent__"` is true on this engine.

**Pushed live after the founder's yes (2026-11-21):** `update_cell` (tool 3), `fill_cells`
(tool 51), `batch_update` (tool 5). The local `batch_update.xs` was behind live (no try/catch,
no telemetry); it was rebuilt from live before the push.

### Live smoke test, 2026-11-21 (fixture map 303 "SAFE-1 smoke (safe to delete)", account 13, run ticket for test user 25)

Every row was re-read from the database afterwards; results below are the stored values, not the tools' own replies.

| Test | Call | Result |
|---|---|---|
| T-SAFE-01-1 | `update_cell`, times only | ✅ text kept; times 30 hours |
| T-SAFE-01-2 | `update_cell`, text only | ✅ all four times and unit kept |
| T-SAFE-01-3 / -5 | `update_cell`, `content: ""` and `planned_duration: 0` | ✅ text cleared; 0 stored |
| T-SAFE-01-6 | `update_cell`, nothing sent | ✅ `nothing_to_change`, nothing written |
| T-SAFE-01-7 | `update_cell` on locked and confirmed cells | ✅ both skipped, rows unchanged |
| T-SAFE-02-2 | `fill_cells`, item with only `actor_fields` | ✅ text and times kept; actor_fields saved |
| T-SAFE-02-5 | `fill_cells`, list with locked + confirmed + 2 writable | ✅ 2 written, 2 skipped with reasons; locked/confirmed rows unchanged (**this was the live bug**) |
| T-SAFE-02-4 | `batch_update`, item with no `content` key | ✅ text kept (was wiped before) |
| T-SAFE-02-6 | `actor_fields` merge | ✅ merged as before |

**Suspect-cell report** (`ops/suspect_wiped_cells`, function 415, read-only): **3 cells**, all on
**map 178** (cells 8264, 8265, 8266), AI-written, no text, times 5 / 2 / 3, last changed
2026-06-24. Not touched (map 178 is the protected baseline). **Founder decision 2026-11-21:
leave them alone** (no earlier text exists to restore from).

**Cleanup:** fixture map 303 deleted (4 cells, 4 lenses, 1 stage; re-query shows 0 cells);
helper function deleted. Kept: `journey/cell_merge_patch` (412), `tests/safe1_cell_merge_cases`
(413), `ops/suspect_wiped_cells` (415). The run ticket expires on its own after 30 minutes.

**Existing suites:** `npm test` in `webapp/protype-2`: ✅ **1017 of 1017 pass** (the app only
names these tools in labels and tests; it does not call them). `npx vitest` reports "no test
suite found" for every file because the project uses Node's own runner; use `npm test`.
**Not run:** `workflow_tests/1–12` (cannot be run from a session, CLAUDE.md) and Playwright.

**Story status:** 01 ✅ done · 02 ✅ done for the three AI tools; the other cell writers listed in
section 2 are not yet reviewed · 03 ⏸ waiting on D-1.

**Differences from the stories:**
- The response field is `fields_set` (what this call wrote), not `fields_changed`: comparing old
  and new values with this engine's loose `==` would be unreliable.
- `actor_fields` keeps today's **merge** behaviour (db.patch merges json). Replace-mode is not built.
- `fill_cells` still writes `status: draft` when an item sets nothing (no `nothing_to_change` skip
  inside its loop): branching on a value computed earlier in the same loop pass is the known
  silent-failure shape. `update_cell` (no loop) does skip with `nothing_to_change`.


### 2026-11-21 — story 03 and the owner role (Fable 5.2)

**New in workspace 1:** table `account_owner` (167, seeded account 2 → user 2 "Jav");
functions `usr/account_rank` (416), `usr/assert_owner_untouched` (417); endpoints
`GET account/owner` (671), `POST admin/user_reset_link` (672).
**Changed (one guard call added to each, nothing else):** `admin/user_role` (11),
`admin/user_status` (586), `admin/user_update` (588), `admin/user_delete` (589).
**App:** Manage users shows "Owner", a reset key button and a one-time link panel; new public page
`/set-password`; sign-in page shows "Your new password is set". Error codes E-SAFE-002, 004–010 in the catalog.

All checks below ran over **real HTTP** against test account 13 with a temporary test owner
(user 22, removed afterwards). Stored rows were re-read; results are not the endpoints' own word.

| Test | Result |
|---|---|
| T-SAFE-03-1 admin makes a link for a member; works once; second use refused; new password signs in | ✅ |
| T-SAFE-03-2 member refused (E-USR-001); no token = 401 | ✅ |
| T-SAFE-03-3 another account's person, and no id = "not found" (E-USR-002) | ✅ |
| T-SAFE-03-4 replaced link refused; cancelled link refused | ✅ (expired = the existing 1-hour check, not waited out) |
| T-SAFE-03-5 earlier sign-ins stop working after a reset | ❌ **Not built.** Xano tokens cannot be revoked; needs its own story |
| T-SAFE-03-6 sixth link in an hour refused (E-SAFE-002) | ✅ |
| T-SAFE-03-7 no event row holds a token (18 SAFE-1 rows read) | ✅ |
| T-SAFE-03-8 admin→admin refused (006); owner→admin allowed; nobody resets the owner (007) | ✅ |
| T-SAFE-03-9 reset within 24 h of an admin's email change refused (E-SAFE-005) | ✅ |
| T-SAFE-03-10 owner told in-app | ⚠ Partly: every link writes a SAFE-1 event (who, for whom, when) for the Health page. There is no notice list in Emgram yet, so no pop-up notice |
| T-SAFE-03-11 no email sent | ✅ (the endpoint calls no mail step) |
| T-SAFE-03-12 UI: key button only where allowed; link shown once with copy/cancel; set-password page reads the link, hides the token from the address bar, refuses a broken link | ✅ in the app. The final "Set password" click was not pressed in the browser; the same two calls passed over HTTP |
| Extra: self (009), AI (010), switched-off (004) refused | ✅ |
| Owner guard: another admin cannot demote, switch off, edit or remove the owner (E-SAFE-008); owner can edit own name; non-owner rows unaffected | ✅ 4 of 4 + 2 controls |
| Unit tests: `teamOwner.test.ts` (4), `resetLink.test.ts` (7) | ✅ |
| `npm test` in `webapp/protype-2` | ✅ **1028 of 1028** |

**Story 02 follow-up — the other cell writers, reviewed (local files):**

| Writer | Verdict |
|---|---|
| `set_cell_status`, `batch_set_status` | Safe: only status/lock keys are patched. Finding: `$input.is_locked != null` is never true for `false`, so the tool can lock but **cannot unlock** |
| `update_actor_cell_fields`, endpoints 604, 605 | Safe: `actor_fields` only |
| Endpoint 44 (the app's own cell save) | Safe: writes only the keys the request sent (`pick` of the raw keys) |
| Endpoint 51 (older map chat) | Text only, times untouched. Finding: skips locked cells but **not confirmed** ones |
| `clone_scenario`, `create_journey_map`, 42, 126, `insert_lens`, `insert_stage`, `ensure_items_row` | Create new cells only; nothing to wipe |

**Open items (not blockers, each needs a founder yes):**
1. Sign-in tokens are not revoked by a reset (T-SAFE-03-5).
2. No in-app notice list exists; owner visibility is the Health page.
3. `set_cell_status` cannot unlock; endpoint 51 overwrites confirmed cells.
4. Public `reset/request-reset-link` reveals which emails have accounts.
5. "Eli Claude" (user 34) is not marked as an AI yet, so it is treated as a person (AIM-1).
6. No user has `is_platform_admin`, so "support resets the owner" is a manual database step.
7. One leftover test event (id 12370) sits in account 2's event log; the log is append-only.

**Not run:** `workflow_tests/1–12` (cannot be run from a session) and Playwright.
