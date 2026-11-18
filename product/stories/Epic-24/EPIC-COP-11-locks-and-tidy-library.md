# EPIC-COP-11 — Locks, and a library that stays tidy

**Status:** 🟡 Server side live (2026-11-18, Sonnet 5.5). Screen (story 05), auto-lock on Undo, and the old-item backfill not built. **Opus review pass still to do.**
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

**Not done / not proven:**
- **Screen (story 05):** lock button, kind filter, "23 of 50", stale filter. API wrappers and display helpers exist; no screen yet.
- **Owner edits and Undo lock automatically (D-24-1):** `skill_write` does it when called as owner, but no owner endpoint calls it yet, and `skill_undo` does not lock.
- **Suggest as an approval item:** the copilot proposes in chat; no approval request is created.
- **Full library (E-COP-091) and word limit:** coded, not hit live (bounds stop a tiny limit; account has about 6 items).
- **Backfill of old free-text kinds:** not run; old items have no meta row so they read as "general".
- **"Least used" hint on a full library:** shows the oldest-updated item, not the least used.
- **Stale flag:** computed on read, no `flagged_stale` event.
- Test item #10 (locked, planning) left in account 13.
