# EPIC-COP-11 — Locks, and a library that stays tidy

**Status:** 🟡 Server side live (2026-11-18, Sonnet 5.5). Screen (story 05) built 2026-11-18. Auto-lock on Undo built 2026-11-19. Old-item backfill built 2026-11-19 (nothing to do: no item is scoped by kind of work). Review pass done 2026-11-18 (Fable 5.2), 3 findings fixed.
**Model:** **Opus 5.5** for story 01 (the lock is a guard). **Sonnet 5.5** for 02–05. Opus review pass at the end.
**Depends on:** COP-9 stories 01–04 (live). **Build together with COP-9 story 05** (trial before trust): both change how items are promoted, flagged and loaded.
**Risk:** medium. Story 01 decides what the AI may never change.

---

## 1. Goal

**Pain:**
- Today the copilot can edit or retire **any** item in "How I work", including text the owner wrote.
- Nothing limits how big the library gets, and every active item is loaded into **every** run. More items means a dearer run, and more chance two items contradict each other.
- Items nobody uses stay forever.
- The `work_kind` scope is free text, so two items can say "planning" and "plans" and never match.

**Fix:**
1. A **lock** on each item. Locked = the AI reads and follows it but can't change it; it can only suggest a change.
2. A **size limit**, enforced on the server.
3. **Unused items flagged** for the owner (never retired automatically).
4. A **fixed list of kinds of work**, so each AI loads only what is for its job.

**Win:** the owner's words are safe, runs stay cheap, and the library stays small enough to read.

### Data (additive; ask before any push)

`copilot_skill` has `filters=trim` text columns, so by the house rule a new field goes in a **1:1 side table**, not a new column (the `updateTableSchema` validator bug).

| New table | Fields | Notes |
|---|---|---|
| `copilot_skill_meta` | `skill_id` (unique), `account_id`, `is_locked` bool, `locked_by_user_id` int, `locked_at`, `work_kind` enum (`map_building`, `planning`, `doing_work`, `research`, `general`), `updated_at` | One row per item. No row = unlocked, `general`. Gets its own `GET` endpoint (AUTH-1 rule) |
| settings (row in an existing settings table, or a small `copilot_library_setting` table) | `max_active_items` (50), `max_load_words` (4000), `stale_after_days` (30) | Thresholds are settings, not code (same rule as COP-9-05) |

"Last used" is **not stored**. It is computed from `copilot_skill_use`, which already records every use.

---

## 2. Stories

### US-COP-11-01 — Lock an item so the AI can't change it

**As an** owner **I want** to lock a skill **so that** the AI never rewrites what I decided.

```gherkin
Scenario: lock and unlock
  When I press "Lock" on an item in "How I work"
  Then it shows a lock, and the change is recorded as a version (changed_by owner, reason "locked")
  And "Unlock" reverses it the same way

Scenario: the AI can't change a locked item
  Given an item is locked
  When the copilot tries to edit or retire it, at any approval level, even "runs on its own"
  Then copilot/skill_write refuses with E-COP-089 and nothing changes
  And a rejected event is logged and the attempt is in tool_call_log

Scenario: the AI can suggest instead
  Given an item is locked
  When the copilot thinks it should change
  Then it creates an approval request (action type skill_write, level forced to "waits for you")
  showing the text before and after, and the item changes only if I approve

Scenario: the AI can't unlock
  Then no AI tool can set or clear a lock; only the owner endpoint can, and only a person (not the copilot user)

Scenario: what I write is locked automatically (D-24-1)
  When I create or edit an item myself, or press Undo
  Then the item is locked unless I untick "let the AI change this"
```

### US-COP-11-02 — A fixed list of kinds of work

**As an** owner **I want** each item tagged with the job it is for **so that** each AI loads only
what helps it.

```gherkin
Scenario: every item has a kind of work
  Then every item has one of: map_building, planning, doing_work, research, general
  And an item with no tag is treated as general

Scenario: the AI must choose from the list
  When the copilot saves an item with a kind of work that isn't on the list
  Then it is refused with E-COP-090 "Pick one of: map building, planning, doing work, research, general."

Scenario: existing items
  Given items saved before this epic with scope work_kind and free text
  Then a one-off backfill maps them to the closest kind, or general, and lists what it did in Test results
  # backfill tested on the test account first; no item is deleted or retired by it

Scenario: loading by kind
  When skill_library is called with a list of kinds
  Then it returns only items of those kinds plus general
  And with no list it behaves exactly as today (all kinds) so the main copilot is unchanged
```

### US-COP-11-03 — A size limit the AI can't exceed

**As an** owner **I want** the library capped **so that** every run stays cheap and readable.

```gherkin
Scenario: the active-item limit
  Given the library has max_active_items active items (default 50)
  When the copilot tries to create one more
  Then it is refused with E-COP-091 "How I work is full. Merge or retire an item first."
  And the copilot is told which items are least used, so it can propose a merge

Scenario: the load limit
  Given the active items for this run add up to more than max_load_words
  Then skill_library loads trusted items first, then trial items, newest use first, until the limit
  And the run records that items were left out, and Health counts it

Scenario: the limits live on the server
  Then they are checked in copilot/skill_write and copilot/skill_library, not in the AI's instructions

Scenario: the owner can change the limits
  Then the three numbers are a settings row the owner can edit, with server bounds (items 10–200, words 1,000–20,000, days 7–365)
```

### US-COP-11-04 — Unused items are flagged, never removed

**As an** owner **I want** to see what the AI no longer uses **so that** I can clear it out in one go.

```gherkin
Scenario: flagged after the quiet period
  Given an active item has not been used for stale_after_days (default 30), counted from copilot_skill_use
  Then it shows "not used in 30 days" in "How I work" and in the weekly summary (COP-9-07)

Scenario: never retired on its own
  Then nothing retires or deletes an item for being unused; the owner, or the copilot under its level, decides

Scenario: a new item isn't stale
  Given an item created less than stale_after_days ago and never used
  Then it is not flagged
```

### US-COP-11-05 — The owner sees it all in "How I work"

**As an** owner **I want** the lock, the kind of work, last used and the limit on one screen **so that**
I don't have to go looking.

```gherkin
Scenario: each item shows
  Then each item shows a lock button, its kind of work, and "last used" (or "never used")

Scenario: the limit is visible
  Then the section header shows "23 of 50 items"

Scenario: filter
  Then I can filter by kind of work and by "not used in 30 days"
```

---

## 3. Governance

- **Tables:** `copilot_skill_meta` (new, 1:1 side table) and a settings row. Additive only. **Ask before the push.** Side table gets `GET /copilot/skill_meta` (no filters, account-scoped).
- **Delete behaviour:** meta rows are never deleted; an unlocked item keeps its row with `is_locked = false`. Locks and kind changes are recorded as versions in `copilot_skill_version`.
- **Validation (server, friendly messages):** lock/unlock only by a person who is an admin of the account; kind of work from the fixed list; limits within bounds.
- **Error codes:**
  - E-COP-089: the item is locked; the AI may suggest a change but not make it
  - E-COP-090: kind of work not on the list
  - E-COP-091: the library is full
  - E-COP-092: lock change refused (not a person, or not an admin)
- **Events:** `copilot.skill.locked` / `.unlocked`, `copilot.skill.refused_locked`, `copilot.library.full`, `copilot.library.load_trimmed`, `copilot.skill.flagged_stale`, each with success and failure.
- **History:** `copilot_skill_meta` is not history (it can change); the version table records every lock change.

## 4. Counter-measures

| Risk | Counter-measure |
|---|---|
| The AI rewrites the owner's text | Owner edits lock by default; `skill_write` refuses locked items at every level |
| The AI unlocks an item itself | No AI tool touches locks; the endpoint refuses the copilot user (E-COP-092) |
| The library grows until runs are slow and dear | Item cap on write; word cap on load; both on the server |
| A useful item gets cut by the load cap | Trusted first, then most recently used; the run records what was left out |
| Stale items are removed by mistake | Flag only. Nothing retires on its own |
| Free-text kinds never match | Fixed list, refused otherwise (E-COP-090) |
| The AI saves a duplicate (seen live 2026-11-18: exception #8 repeated #6) | Prompt: check the library before saving; `skill_write` refuses a new item whose title and body match an active item of the same kind and parent (case and spaces ignored), pointing to the existing number |
| `|contains:` used for kind matching | Use `in` inside the `db.query` where clause (CLAUDE.md rule) |

## 5. Test plan

| ID | Type | Checks |
|---|---|---|
| FT-COP-11-01 | Function | Locked item: edit and retire refused at wait, tell and own; suggestion creates an approval at "wait" |
| FT-COP-11-02 | Function | Copilot user can't lock or unlock (E-COP-092); owner can; both make a version |
| FT-COP-11-03 | Function | Kind not on the list refused (E-COP-090); load by kind returns only those plus general |
| FT-COP-11-04 | Function | 51st item refused (E-COP-091); load over the word cap keeps trusted first and logs the trim |
| FT-COP-11-05 | Function | Item unused 31 days flagged; new unused item not flagged; nothing retired |
| FT-COP-11-06 | Function | Backfill on a clone/test data maps old free-text kinds; no item deleted |
| UT-COP-11-* | Unit | Error codes in catalog; schema manifest entry; display helpers (lock, last used, "23 of 50") |
| UI-COP-11-* | Playwright | Lock button, kind filter, stale filter, item counter |
| AI-COP-11-01 | Real AI chat | Ask the copilot to change a locked skill: it proposes instead of editing |

## 6. Test results

**Tables added (founder approved 2026-11-18):** `copilot_skill_meta` (id 165), `copilot_library_setting` (id 166). Additive only; nothing existing changed.

**Live items:** `copilot/skill_write` (398, now checks lock, kind, cap, duplicate), `copilot/skill_library` (399, kinds filter, word limit, "locked" marker, `left_out`), `save_skill` tool (183, passes `work_kind`), endpoints 666 `copilot/skill_lock`, 667 `copilot/skill_meta`, 668 `copilot/library_settings`.

| Check | Result |
|---|---|
| Locked item, copilot edits it (live function) | refused **E-COP-089**, nothing changed |
| Kind "bogus" (live function) | refused **E-COP-090** |
| Same title and text again, different case (live function) | refused **E-COP-096**, points to #10 |
| Library loader, no kinds | all items, #10 marked `locked`; `left_out` 0 |
| Library loader, kinds ["research"] | #10 (planning) left out; untagged items still load |
| HTTP as test admin (`tests/cop11_probe.py`) | **14/14**: read endpoint, lock/unlock each make a version, foreign item refused, 3 out-of-bounds settings refused, in-bounds saved and read back, no sign-in refused |
| Real copilot asked to rewrite locked #10 (`tests/cop11_ai_probe.py`) | **2/2**: item unchanged; it said it is locked and suggested the change |
| Unit (`cop11Library.test.ts`) | 11/11; full `npm test` 954/954; tsc clean |

### Review pass (2026-11-18, Fable 5.2)

| Finding | Fix | Proof (live) |
|---|---|---|
| The copilot could add an exception under a locked skill ("WHEN always, do the opposite"); proven, it saved #11 | `skill_write` reads the parent's lock; copilot create or edit of an exception or link under a locked skill is refused (E-COP-089) | Same call now refused; #11 retired |
| A word limit above 4,000 did nothing: an old 24,000-character cut still applied, silently | The cut is now a backstop at the largest allowed limit | Loader runs, same output; not exercised with a large library |
| Duplicate check ignored an exception's "when" | The "when" is compared too | Same title/text + same when refused (points to #8); different when saved (#12, then retired) |

Checked and found sound: retire of a locked item refused; a lock and a copilot edit racing each other cannot both commit (both claim the same version number); only `skill_write`, `skill_undo` and endpoint 666 write these tables; `save_skill` and `retire_skill` are not on the outside Claude door.

### Story 05: the screen (2026-11-18, Fable 5.2)

In the copilot panel's "How I work" list (`CopilotPanel.tsx`, `SkillsSection`): each item shows Locked / AI may change, its kind of work and "Used today" / "Never used"; an admin gets Lock / Unlock; the header shows "6 of 50 items", a kind-of-work filter, a "Not used in 30 days" filter, and a Limits form (admin). A limit outside the bounds is refused on the screen with the typing kept; the server checks again. If the side-table read fails, the list still shows without the extras.

| Check | Result |
|---|---|
| Unit: `skillsModel.test.ts` UT-COP-11-20..22 (join, filters, limit bounds) | 3/3 |
| Playwright, live test account, signed in (`e2e/copilot-skills.spec.ts`) | **5/5**: UI-COP-11-01 lock, kind, last used, counter; UI-COP-11-02 unlock then lock, kind filter; UI-COP-11-03 bad limit refused, typing kept; plus the two COP-9 specs still pass |
| Full `npm test` / tsc | 958/958; clean |

Not covered by a browser test: the stale filter with a truly stale item (none exists in the test account), and saving in-bounds limits from the screen (the HTTP probe covers the endpoint).

### Auto-lock on Undo (2026-11-19, Sonnet 5.5)

`copilot/skill_undo` (live fn 400) now locks the item in the same transaction as the undo, so a failed undo leaves no lock. Live proof on the test account: the copilot created and edited throwaway item #13 (allowed, unlocked); the owner pressed Undo (version 3); the copilot's next edit was refused with **E-COP-089**. #13 retired afterwards. Unit test UT-COP-11-13.

**Not done / not proven:**
- **AI identity at the lock endpoint:** it reuses `copilot/assert_person_only` (refuses with E-COP-025, not E-COP-092); not run live as the copilot user. E-COP-092 is catalogued but nothing emits it.
- **No caller passes kinds yet:** chat, runs and `get_how_i_work` all load every kind.
- **Owner edits lock automatically (D-24-1):** `skill_write` does it when called as owner, but no owner edit screen or endpoint calls it yet (Undo now does lock).
- **Suggest as an approval item:** built 2026-11-19, see below.
- **Full library (E-COP-091) and word limit:** coded, not hit live (bounds stop a tiny limit; account has about 6 items).
- **Backfill of old free-text kinds:** not run; old items have no meta row so they read as "general".
- **"Least used" hint on a full library:** shows the oldest-updated item, not the least used.
- **Stale flag:** computed on read, no `flagged_stale` event.
- Test item #10 (locked, planning) left in account 13.

### Old-item backfill (2026-11-19, overnight, Opus 5.5)

`copilot/backfill_work_kinds` (function 408): maps a free-text kind of work to the fixed list (or general) for items scoped `work_kind`; only fills a kind that is not set; never overwrites, deletes, retires or locks; dry_run reports only; writes need one named account. Unit `cop11Backfill.test.ts` 4/4.
**Live dry run across all accounts: 0 items.** Confirmed directly: no `copilot_skill` row has scope_type `work_kind`. So no real run was needed and none was made. The function stays for any later import.

### "Suggest instead" as a real approval item (2026-11-19, overnight, Opus 5.5)

**Built:**
- `save_skill` (tool 183) looks up the lock in the caller's own account; if the item (or the skill an exception changes) is locked, the request goes through the gate with `act_force_wait`, so it ALWAYS waits for the owner (E-COP-020), whatever the level, with "Before: ... After: ..." in the Approvals item.
- `journey/tool_gate` (311) passes `act_force_wait` through; `copilot/action_gate` (330) turns it into "wait". Forcing can only make an action wait.
- On the approved re-send, `save_skill` passes the action id the gate just claimed; `copilot/skill_write` (398) lets the locked edit through only after checking the database itself: an approved or edited `skill_write` item of this account whose request names the same item and parent. A retire of a locked item is never let through. The lock stays on.

**Found and fixed on the way:**
- The push-time review caught that the gate's decision branches still read the stored level, so a forced wait at "tell" or "own" went straight through (then refused). Fixed before anything was pushed (UT-COP-11-S-05).
- **Older bug:** `get_approval` (161) only showed approvals of the chat's business, but skill changes are filed under the copilot home (COP-9 story 06), so no approved skill change could ever be finished from a business chat (E-COP-036). Now a `skill_write` item under this account's home is found from any business chat (UT-COP-11-S-06).

| Check | Result |
|---|---|
| Unit `cop11Suggest.test.ts` UT-COP-11-S-01..06 (+ UT-COP-11-07 narrowed to "never sets or clears a lock") | pass; full suite **1015/1015** |
| Real AI (`tests/cop11_suggest_probe.py`, conversation 227, item 50) | **8/8**: locked #10 change waited with before and after; nothing changed until approved; after approval the copilot re-sent it, #10 changed and stayed locked; clean-up Undo put #10 back |

**Seen on the way (not fixed):** the chat history the copilot gets holds the text of earlier turns but not its tool calls, so in one turn it doubted (and wrongly withdrew) a change it had really made. Earlier test runs left approved/used items 48-50; #10 was put back each time.
