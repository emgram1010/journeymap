# GUARD-1 — Build Guards

**Epic ID:** GUARD-1
**Feature:** Mistakes that nothing in the build could catch now fail the build.
**Status:** **01, 02, 03 done** (2026-10-18, verified live). **04 to-do.** *(to-do / in-progress / done)*
**Raised by:** founder question, 2026-10-18 — *"what do we need to do so you improve... to avoid these bugs?"*
**Goal:** Turn the classes of bug that keep recurring into automated checks, so they are caught by `npm test` rather than by someone noticing.

---

## Why

Across phase-5's gap-fix work, five bugs were introduced and caught in the same session. Every one of them passed typecheck, passed the test suite, and pushed cleanly. They were found by grepping by hand, or by opening a browser — neither of which is a process.

Worth stating plainly: **these are the author's own mistakes**, not inherited ones. The point of this epic is that the next one is caught automatically.

| Bug | What would have caught it |
|---|---|
| `E-SCHED-002/003` reused for two new meanings | A registry check — **GUARD-1-01** |
| Renumbered the message but not the logged code | The same check, pairing them — **GUARD-1-02** |
| `journey_map_version` protected only by luck | A delete guard — **GUARD-1-03** |
| A spec that skipped silently every run | A skip check — **GUARD-1-04** |
| A one-way door: `schedule` with no `unschedule` | An inverse-operation audit — **GUARD-1-05** |

## Rule

**A rule the team relies on should fail the build when broken, not be remembered.**

## Non-Goals

- Not a linting project. Each guard exists because a specific bug got through.
- No guard that cries wolf: a check with false positives gets switched off, which is worse than no check.

---

## Stories

### US-GUARD-1-01 — An error code means exactly one thing ✅ Done

> **As** the only support person,
> **I want** each error code to have one meaning,
> **so that** when someone quotes a code at me, the catalog tells me the right thing.

```gherkin
Feature: Error codes are unique and documented

  Scenario: A code is emitted that the catalog does not have
    Given an endpoint emits "E-FOO-001"
    And errorCatalog.json has no E-FOO-001
    When the test suite runs
    Then the build fails naming the file and line

  Scenario: A code is reused for a second meaning
    Given E-SCHED-002 means "enter a duration between 1 and 1,440 minutes"
    When an endpoint emits "That day is already live. (E-SCHED-002)"
    Then the build fails saying the catalog may be stale or the code reused

  Scenario: A genuinely generic code is allowed to vary
    Given E-VAL-001 is "this is required" and names the field in each message
    And its catalog entry sets message_varies
    Then those messages do not fail the build

  Scenario: A message built at runtime is not guessed at
    Given a message is assembled with "~" from a variable
    Then its text is not compared, and the code is still checked
```

**Counter-measures**

| Risk | Counter-measure |
|---|---|
| Too strict → false positives → guard switched off | `message_varies` is opt-in **per catalog entry**, so escaping the check is a decision someone records, not a default. It found 12 legitimate `E-VAL-001` variations on the first run. |
| Concatenated messages can't be verified | They are counted and skipped, and the count is reported, so the gap is visible rather than silently assumed covered. |

**Outcome:** found **six pre-existing collisions** on first run — `E-PLAN-001/004/010`, `E-PLN-010/011`, `E-SCHED-001` — each meaning two unrelated things. All renumbered (→ `E-PLAN-014/015/016`, `E-PLN-017/018`, `E-SCHED-008`) across 6 endpoints, plus `E-P3A-002/003` which were shown to users with no catalog entry at all.

---

### US-GUARD-1-02 — The code logged and the code shown must match ✅ Done

> **As** the only support person,
> **I want** the code in the log to be the code the user saw,
> **so that** I don't look up the wrong failure and confidently explain the wrong thing.

```gherkin
Feature: One failure, one code

  Scenario: The logged code drifts from the shown code
    Given reject_code is set to "E-PLAN-004"
    And the message beside it ends "(E-PLAN-015)"
    When the test suite runs
    Then the build fails naming both codes and both lines

  Scenario: A matched pair passes
    Given reject_code is "E-PLAN-015"
    And the message ends "(E-PLAN-015)"
    Then the build passes
```

**Counter-measures**

| Risk | Counter-measure |
|---|---|
| The guard only knows the house shape | It matches a message's code against the nearest bare code assignment above it, which is the shape every endpoint here uses. A new shape would simply not be checked — a gap, not a false alarm. |

**Written immediately after making this exact mistake** while fixing GUARD-1-01: every message was renumbered and every `reject_code` beside it was left on the old value. Found by reading the file before pushing. Nothing else would have caught it.

---

### US-GUARD-1-03 — Nothing deletes the record ✅ Done

> **As** someone whose live work depends on frozen snapshots,
> **I want** the tables that hold the record to be undeletable,
> **so that** a well-meant tidy-up can't silently strip the instructions from work in flight.

```gherkin
Feature: History tables are protected in code

  Scenario: Something deletes a history table
    Given a file contains "db.del journey_map_version"
    When the test suite runs
    Then the build fails, saying what breaks if that row goes

  Scenario: journey_map is still deletable
    Given a file contains "db.del journey_map"
    Then the build passes
    # the map is deletable; its versions are not

  Scenario: A governed exception is allowed, in its own file only
    Given tasks/11_prune_event_log.xs deletes from event_log on a retention policy
    Then that file passes
    And the same statement in any other file fails

  Scenario: An append-only link table is not treated as history
    Given planner_task_work_task is append-only in shape
    And O4 legitimately deletes one when unscheduling
    Then that delete passes
```

**Counter-measures**

| Risk | Counter-measure |
|---|---|
| A legitimate delete is blocked and the guard gets weakened | `ALLOWED_DELETES` names the exception **file by file with a reason**, so the same statement elsewhere still fails. Found the real case on first run (`event_log` retention prune). |
| Append-only *shape* confused with *history* | Deliberately different lists. `schemaAudit` asks "does this table have `updated_at`"; this asks "is this row a record of something that happened". |

Protects: `journey_map_version`, `plan_publication`, `activity_log`, `plan_change_log`, `event_log`. The rule is also stated at the top of `112_journey_map_version.xs`.

---

### US-GUARD-1-04 — A skipped test is reported, not counted as green ⏸ To-do

> **As** someone relying on the suite,
> **I want** a silently skipped spec to be visible,
> **so that** "all passing" means the tests actually ran.

```gherkin
Feature: Skips are not passes

  Scenario: A spec skips while a token is available
    Given E2E_AUTH_TOKEN is set
    When a Playwright spec calls test.skip()
    Then the run reports it prominently
    And the summary does not read as fully green

  Scenario: No token
    Given E2E_AUTH_TOKEN is not set
    Then skipping is expected and reported once, not per spec
```

**Counter-measures**

| Risk | Counter-measure |
|---|---|
| Legitimate conditional skips become noise | Only skips **while a token is present** are treated as suspicious — that is the case where a spec should have been able to run. |

**Why it matters:** `E2E-W5-01` skipped on every run because it raced a reload and read the loading spinner as "not empty". In a summary line that is indistinguishable from a pass.

---

### US-GUARD-1-05 — Every create has a way back ⏸ To-do

> **As** someone using the product,
> **I want** anything the UI can create or claim to be undoable,
> **so that** a misclick isn't permanent.

```gherkin
Feature: Inverse operations exist

  Scenario: A mutation has no inverse
    Given POST work_task/{id}/schedule exists
    And no endpoint removes that link
    When the audit runs
    Then it reports the missing inverse

  Scenario: A deliberate one-way operation
    Given publishing a version is intentionally permanent
    And it is listed as such with a reason
    Then it is not reported
```

**Counter-measures**

| Risk | Counter-measure |
|---|---|
| Not everything should be reversible | An allow-list with reasons, same pattern as GUARD-1-03. Publishing a version is permanent on purpose. |
| Static analysis can't infer intent | It reports *candidates for review*, not failures — the one guard here that informs rather than blocks. |

**Why it matters:** `SCHED-1` shipped `schedule` with no `unschedule`. Harmless while jobs were created by API call; the moment GAP-FIX W1 put a Schedule button in front of a planner it became a one-way door. Fixed as O4, but only after it shipped.

---

## Governance

- **No new tables.** Guards are TypeScript tests in `webapp/protype-2/src/ops/`.
- **No new error codes** — these fail the build, they don't surface to users.
- Each guard reports **what breaks**, not just that a rule was violated.
- Every exception is named with a reason in code, never a silent carve-out.

## Test Results

| ID | Result |
|---|---|
| GUARD-REG-01 — every emitted code means one thing | ✅ Found 6 pre-existing collisions + 2 undocumented codes; all fixed |
| GUARD-REG-02 — logged code matches shown code | ✅ Caught the author's own renumbering slip before it shipped |
| GUARD-DEL-1-01 — nothing deletes the record | ✅ Found 1 legitimate exception (`event_log` retention prune), now allow-listed |
| Suite | **399/399**, `tsc` clean, `vite build` clean |

## Still open

- **US-GUARD-1-04** and **US-GUARD-1-05** not started.
- The guards cover `apis/`, `functions/` and `tasks/`. They do **not** scan `webapp/` — a frontend file inventing an error code would not be caught.
- `CLAUDE.md`'s build protocol still has **no step that says look at the screen**, which is what actually found three of this session's bugs. Proposed, not yet added — the founder's call.
