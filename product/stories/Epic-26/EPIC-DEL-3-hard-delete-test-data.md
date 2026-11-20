# DEL-3 — HARD delete: permanently remove test data

**Epic ID:** DEL-3
**Kind of delete:** 🔴 **HARD. PERMANENT. It cannot be undone.** Rows are removed from the database.
**Status:** 📋 Written, not built (2026-11-20). **Do not start until DEL-2 is done and the founder says go.**
**Depends on:** DEL-2 (an item must be archived before it can be hard deleted), DEL-1 (Epic-6).
**Raised by:** founder, 2026-11-20. Test data (a sample map with 7 jobs) cannot be removed because Emgram never deletes work history.
**Read first:** `README.md` in this folder. It holds the safety rules and what to tell the founder before you start.

---

## 1. Goal

A person who owns the account can permanently remove an item that is **marked as test data**,
together with everything created from it, after seeing exactly what will go. Nothing else can be
hard deleted. The AI agent can never do it.

The example (a test map with its jobs) shows the pattern. Build it for "an item and everything
under it", not for one literal map.

## 2. Decisions

| # | Decision | Who |
|---|---|---|
| D-1 | Hard delete is rare. It exists for test data only in this epic. | founder, 2026-11-20 |
| D-2 | Privacy erasure for a customer and closing an account are real needs, but they are a **later epic**, not this one. | founder, 2026-11-20 |
| **D-3 (OPEN, needs the founder's yes before story 03)** | Removing test data fully means also removing its frozen versions, activity log and jobs. That **breaks DEL-1's rule "frozen versions never go" on purpose**, for test-marked data only, and needs a named exception in the history guard (`historyTables.ts`). The alternative is to keep those rows and delete only the map content. | **not decided** |

## 3. What exists today

Checked in the repo files on 2026-11-20. **Live Xano was not compared; DEL-2 story 01 does that.**

| Fact | Where |
|---|---|
| `hard: true` on the business delete destroys the business and every map in it, through one cascade function | api 69, `functions/journey/delete_map_cascade.xs` |
| That hard delete is refused when any map is used by a plan or template or has jobs (E-DEL-001) | `journey/assert_map_unused` |
| A guard test fails the build if anything deletes from `journey_map_version`, `plan_publication`, `activity_log`, `plan_change_log` or `event_log`. One named exception exists (the event-log prune) | `webapp/protype-2/src/ops/historyTables.ts` |
| A real map was once lost by a delete, before the guards existed. Its jobs survived only because versions are never deleted | DEL-1 Test results, "A real loss" |
| `db.del` by field removes only the FIRST matching row | CLAUDE.md |

## 4. Rule

**Only a person who owns the account can hard delete. Only an item marked as test data. Only
after it is archived, after a dry run they have read, and after typing its name. Everything is
removed in one transaction or nothing is. A receipt stays forever.**

## 5. Do not break

- Real (unmarked) data keeps every protection it has today. This epic adds no way around E-DEL-001 for it.
- The history guard is not loosened in general. Any exception is named file by file, with its reason, like the existing one.
- The copilot's own playbook business can never be marked as test or deleted.
- `event_log` keeps the record of the delete itself. The receipt is never deleted.

## 6. Non-goals

- Privacy erasure, account closure, bulk delete across accounts.
- Any AI tool, scheduled task or outside-door (MCP) call that hard deletes.
- Deleting real data "just this once". If that need appears, stop and ask the founder.

---

## 7. Stories

### US-DEL-3-01 — Mark an item as test data

**As** the owner **I want** to mark a business, map or plan as test data **so that** only things I chose can ever be removed for good.

```gherkin
Scenario: mark as test
  Given I own the account (or am an account admin)
  When I mark an item as test data and give a reason
  Then a mark is stored with who, when and why
  And the item shows a "Test data" badge everywhere it is listed
  And a "marked_test" event is logged

Scenario: the mark is not a shortcut
  Given an item has jobs that customers or other people worked on
  When I mark it as test
  Then I see how many jobs and how many different people worked on it, and must confirm

Scenario Outline: who cannot mark
  When <who> tries to mark an item as test
  Then it is refused (E-DEL-007)

  Examples:
    | who                          |
    | the AI agent (any identity)  |
    | a teammate who is not admin  |
    | anyone, on the copilot's own playbook business |
```

- A new 1:1 side table (suggested `test_data_mark`: entity_type, entity_id, account_id, marked_by, reason). Unique on (entity_type, entity_id). Ask before the schema push.
- Marking a business marks what is inside it. Unmarking is allowed until the hard delete runs.

### US-DEL-3-02 — Dry run: see exactly what would be removed

**As** the owner **I want** a full list of what will go **so that** I never delete more than I meant.

```gherkin
Scenario: dry run
  Given an item marked as test AND archived (DEL-2)
  When I open "Delete permanently"
  Then I see a count for every table that would lose rows (maps, stages, cells, versions, jobs, tasks, log entries, plan links)
  And I see anything OUTSIDE the item that points at it (a plan or template that is not test data)
  And nothing has been deleted

Scenario: something real depends on it
  Given a plan that is NOT test data uses a map inside the item
  Then the hard delete is refused, naming that plan (E-DEL-005)
  And I am told to remove the map there or mark that plan as test too

Scenario: not ready
  Given the item is not marked as test, or not archived
  Then "Delete permanently" is refused and says which step is missing (E-DEL-005)
```

- ONE function builds the list (suggested `harddelete/plan`). The real delete in story 03 uses the SAME function to decide what to remove, so the preview and the delete cannot disagree.
- The dry run returns a fingerprint of the counts. It is not a permission; it only proves what the person saw.

### US-DEL-3-03 — The hard delete

**As** the owner **I want** the test data gone for good **so that** my lists, reports and counts hold only real work.

```gherkin
Scenario: delete permanently
  Given I have read the dry run
  When I type the item's exact name and press "Delete permanently"
  Then the server re-runs the plan and compares it with the fingerprint I saw
  And everything in the plan is removed in ONE transaction, children before parents
  And a receipt is written with who, when, the item's name and the count removed per table
  And a critical-severity event appears on Health

Scenario: the data changed since the dry run
  Given a job was added after I opened the dry run
  When I confirm
  Then nothing is deleted and I am shown the new dry run (E-DEL-006)

Scenario: wrong name typed
  Then nothing is deleted (E-DEL-006) and my typing is kept

Scenario: something fails halfway
  Then the transaction rolls back and nothing is deleted
  And a "failed" event is logged with the step that failed

Scenario Outline: who can never run it
  When <who> calls the hard delete
  Then it is refused (E-DEL-007), at every approval level

  Examples:
    | who                                            |
    | the AI agent, with or without an approval      |
    | a call through the outside MCP door            |
    | a scheduled task                               |
    | a teammate who is not the owner or an admin    |
```

- Person-only, from the app screen. There is no AI tool for it and none is added to the MCP server. A source-reading test checks that no file under `ai/` calls the hard-delete function.
- Many rows: `db.query`, then loop and `db.del` each by `id`, inside `db.transaction` (CLAUDE.md). Never rely on delete-by-field.
- If D-3 is "yes": the history-guard exception is added for this ONE function file, with the reason written next to it.
- A unique index on the receipt (entity_type, entity_id) stops the same delete running twice at once.

### US-DEL-3-04 — The receipt, and a copy before it goes

**As** the support person **I want** proof of every hard delete **so that** "where did it go?" always has an answer.

```gherkin
Scenario: receipt
  When a hard delete finishes
  Then a permanent receipt row holds: who, when, account, item name, reason, counts per table
  And Health has a "Permanently deleted" list that reads from it

Scenario: copy first (optional for the owner)
  Given the dry run screen
  When I press "Download a copy first"
  Then I get one file with the item's maps and job history
  And the hard delete does not depend on me downloading it
```

- New append-only table (suggested `hard_delete_receipt`). Added to `historyTables.ts` so nothing can ever delete from it.

---

## 8. Governance

| Area | Rule |
|---|---|
| Tables | Two new tables (`test_data_mark`, `hard_delete_receipt`). No change to an existing table. **Ask before each schema push.** |
| Delete behaviour | The only `db.del` statements live in ONE function, run inside ONE transaction, driven by the same plan the dry run showed. |
| Validation | Marked as test + archived + dry run fingerprint + typed name + owner or admin + a person. All checked on the server, every time. |
| Error codes (proposed; check the catalog for free numbers first) | `E-DEL-005` not ready, or something real depends on it. `E-DEL-006` confirmation does not match, or the data changed. `E-DEL-007` only the owner (a person) can do this. |
| Events | `marked_test`, `unmarked_test`, `hard_delete_dry_run`, `hard_delete_rejected`, `hard_delete_done` (critical), `hard_delete_failed`. |
| Rollback | There is none for a finished hard delete. That is why it is test-marked data only, archived first, with a receipt and an optional copy. The feature itself is behind a flag per account, off by default. |

## 9. Counter-measures

| Risk | Counter-measure |
|---|---|
| Real data is deleted | Must be marked as test by the owner, with a reason, then archived, then previewed, then named. Four separate steps; none can be skipped on the server. |
| The preview and the delete disagree | One function produces both. The fingerprint is compared again inside the transaction. |
| Only some rows are deleted (orphans) | Loop by id in a transaction; a test compares the dry-run counts with the receipt counts; an orphan check runs after. |
| The AI or an outside tool triggers it | No tool exists. The function checks the caller is a person from the app (`copilot/assert_person_only`), and a test scans `ai/` for any call. |
| A builder tests it on real data | Build and test on **test account 13 fixtures only**. Never on account 2. Never on map 178 or its business. See README. |
| The history guard gets weakened for everything | The exception is one named file with a written reason. The guard still fails for any other file. |
| Two people confirm at once | Unique index on the receipt; the second insert fails and its transaction rolls back. |
| Someone marks real work as test to get rid of it | Owner or admin only, shows how many people worked on it, logged, visible on Health, and the receipt is permanent. |

## 10. Test plan

| Layer | Tests |
|---|---|
| Unit (source-reading) | The one delete function is the only file with `db.del` on these tables; every refusal exists; nothing under `ai/` or `tasks/` calls it; receipt table is in `historyTables.ts` |
| Functional (live, **account 13 fixtures only**) | Every Gherkin scenario through real HTTP; counts before and after; orphan check after; rollback proven by forcing a failure on a scratch copy |
| Real AI | The agent is asked to delete permanently and is refused |
| UI (Playwright) | Mark as test, dry run screen, wrong name keeps typing, success shows the receipt |
| Regression | `npm test`, `workflow_tests/1–12`, existing Playwright specs, and the DEL-1 guard tests unchanged |

## 11. Model guidance

**Opus 5.5 (or stronger) for every story in this epic**, with an independent review pass before story 03 is pushed. Haiku 5.5 only for fixtures.

## 12. Test results

*(Empty. Filled in as each story is built.)*
