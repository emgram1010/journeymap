# DEL-1 — Map & Architecture Delete Safety

**Epic ID:** DEL-1
**Feature:** Deleting a journey map or an architecture no longer leaves orphaned content behind, and never breaks a plan or a job that depends on it.
**Status:** To-do *(to-do / in-progress / done)*
**Depends on:** — (all tables and endpoints involved already exist)
**Raised by:** founder question, 2026-10-18 — *"if I delete an architecture or journey map will it cause any issues, including orphan records?"*
**Goal:** Make the two delete buttons that already exist in the UI safe to press: refuse when something depends on the map, take the map's own content with it when it goes, and never touch the frozen versions that live work reads from.

---

## Why

The question was asked, the code was checked, and the answer is **yes — and it has already happened.** Measured against the live workspace on 2026-10-18:

| Orphaned rows today | Count |
|---|---|
| `journey_cell` | **583** |
| `journey_lens` | 78 |
| `journey_stage` | 55 |
| `journey_map_version` | 3 |
| **Plans pointing at a deleted map** | **1** |
| **Templates pointing at a deleted map** | **2** |
| Jobs with a dead version | 0 ✅ |

Both deletes are reachable from the UI today — the Dashboard, the Architecture Detail page and the Scenarios tab all have a Delete control, each behind a two-step confirm that says nothing about what will be lost.

**What each one actually does:**

| | Deletes | Leaves behind |
|---|---|---|
| `DELETE journey_map/{id}` (api 22) | The map row, and `journey_link` rows where it is source or target | **Every stage, lens and cell it contained**, its `journey_map_version` rows, `journey_stage_owner`, `journey_lens_planned_work`, `plan_template_map`, `planner_workspace_map`, `stage_automation_config`, `automation_snapshot`, conversations, tool/turn logs |
| `DELETE journey_architecture/{id}` (api 69) | Cascades properly: messages → conversations → cells → lenses → stages → maps → architecture | `journey_map_version`, the side tables, `plan_template_map`, `planner_workspace_map`, automation config and snapshots, and any `journey_link` owned by a **different** architecture |

**Execution is currently safe, by accident.** A job reads `work_item.journey_map_version_id → journey_map_version.snapshot`, which is a self-contained copy of the definition. Deleting the map does not delete versions, so live and historical work keeps its instructions — zero jobs affected. **That safety depends entirely on orphaned versions never being cleaned up, and nothing in the code says so.** A well-meaning tidy-up of those 3 orphan versions would silently strip the instructions from live work. That is the most dangerous thing in this epic, and it is a comment away from being safe.

## Rule

**A map can only be deleted while nothing depends on it. When it goes, its own content goes with it. Its frozen versions never go.**

Same shape as the rule P3A-1 already applies to plans, agents and timelines: *delete is allowed only while nothing has happened yet.*

## Existing Architecture (Do Not Break)

- **`journey_map_version` is append-only and permanent.** It is the Definition layer's frozen record and the only thing standing between a map delete and a broken job. Nothing in this epic may delete one.
- **Reference, do not copy.** Jobs read their snapshot through the version, never the live map. This epic must not introduce a copy of map content anywhere.
- Architecture delete's existing cascade order (messages → conversations → cells → lenses → stages → maps) is correct and stays.
- Deleting a map with genuinely nothing attached keeps working exactly as it does now.

## Non-Goals

- No change to how maps are created, edited or published.
- No undo/restore (a Trash feature is a separate epic).
- No change to architecture-level delete *permissions* beyond what US-DEL-1-05 covers.

---

## Stories

### US-DEL-1-01 — A map in use can't be deleted

> **As a** planner,
> **I want** the system to stop me deleting a map that a plan or template is using,
> **so that** I don't silently break a plan I'm relying on and only find out when a job refuses to be created.

**Error code:** `E-DEL-001` — *"This map is used by a plan or template. Remove it there first."*
The message names them, because "something uses it" that doesn't say what is not actionable.

```gherkin
Feature: Refuse to delete a map that something depends on

  Scenario: The map is attached to a plan
    Given a journey map "Quote Request Handling"
    And a plan "Quotes week of Oct 19" has that map attached
    When I delete the map
    Then the delete is refused with E-DEL-001
    And the message names "Quotes week of Oct 19"
    And the map, its stages, its lenses and its cells are all still there

  Scenario: The map is on a template's roster
    Given a journey map "Receiving SOP"
    And a plan template "Weekly Ops" lists that map
    When I delete the map
    Then the delete is refused with E-DEL-001
    And the message names "Weekly Ops"

  Scenario: The map has jobs that were created from it
    Given a journey map with a published version
    And a job was created from that version
    When I delete the map
    Then the delete is refused with E-DEL-001
    And the message says work has been done from this map

  Scenario: Nothing depends on the map
    Given a journey map that no plan, template or job references
    When I delete the map
    Then the map is deleted
    And no plan or template is affected

  Scenario: The refusal is recorded
    Given a delete is refused
    Then a "rejected" event is logged against the map with error_code E-DEL-001
    And it is visible on the Health page
```

**Counter-measures**

| Risk | Counter-measure |
|---|---|
| The check is added but the UI deletes optimistically, so the row vanishes from the screen and comes back on reload | The three delete handlers already restore the row on a thrown error. The refusal must surface as a visible message, not a silent restore. |
| A dependency type is missed (e.g. templates checked, jobs forgotten) | One shared function, `journey/assert_map_unused`, lists every dependency in one place. Both the map delete and the architecture cascade call it — no second opinion. |
| It blocks a map the planner genuinely wants gone, with no way forward | The message says exactly where to remove it first. Once O10 (remove a map from a plan) exists there is a real path; until then the planner can archive the map instead. **Flagged: O10 becomes a dependency for the delete path to be usable.** |
| The dependency check is slow on a big account | Three counting queries, no row loading. Same shape as `planner/workspace_has_history`. |

---

### US-DEL-1-02 — A map's frozen versions are never deleted

> **As the person who has to trust what Execution shows,
> I want** a map's published versions to survive the map itself,
> **so that** work already in flight keeps the instructions it was given, and finished work stays auditable.

This story is mostly **a rule written down and enforced**, because the behaviour is already correct by accident and nothing protects it.

```gherkin
Feature: Frozen versions outlive the map

  Scenario: Deleting a map leaves its versions intact
    Given a journey map with 3 published versions
    And nothing depends on the map
    When the map is deleted
    Then all 3 journey_map_version rows still exist
    And any job pinned to one of them still returns its full instructions

  Scenario: Deleting an architecture leaves its maps' versions intact
    Given an architecture containing two maps, each with published versions
    When the architecture is deleted
    Then every journey_map_version row still exists

  Scenario: A performer's day is unaffected
    Given a published day containing steps from a job pinned to version 2
    When the job's map is deleted
    Then the performer still sees every step's task text and done-when
    And the variance report still computes

  Scenario: The guard catches anyone adding a version delete
    Given a developer adds a db.del against journey_map_version
    When the test suite runs
    Then the append-only guard fails the build
```

**Counter-measures**

| Risk | Counter-measure |
|---|---|
| **The real risk: someone "cleans up" the orphan versions and silently breaks live work.** | A comment in `journey_map_version.xs` and in both delete endpoints saying *why* they survive. Plus an automated guard: `journey_map_version` joins GOV-1's `appendOnly` manifest, and a test fails on any `db.del` against it anywhere in `apis/` or `functions/`. |
| US-DEL-1-03's cascade is written and sweeps versions up with everything else | The cascade function takes an explicit allow-list of child tables. `journey_map_version` is not on it, and a test asserts it is not. |
| Orphan cleanup (US-DEL-1-04) deletes them | That story explicitly excludes versions, and says why. |

---

### US-DEL-1-03 — Deleting a map takes its own content with it

> **As a** founder keeping the database honest,
> **I want** a deleted map's stages, lenses and cells to go with it,
> **so that** the database reflects what exists and a future migration or audit isn't reading hundreds of rows belonging to maps nobody can see.

**⚠️ This story needs a decision before it is built.** Two options:

| Option | What it does | Trade-off |
|---|---|---|
| **A — Cascade** (matches architecture delete) | Delete stages, lenses, cells and side tables along with the map | Consistent with api 69, no new concepts. **Permanently destroys content with no undo.** |
| **B — Soft delete** (matches the rest of this codebase) | Mark the map deleted and hide it; content stays, queries filter it out | Nothing is ever lost; reversible. Adds a flag to filter on in every map query, and the orphans remain (just labelled). |

**Recommendation: A, but only because US-DEL-1-01 lands first.** Once a map in use cannot be deleted at all, the only maps that can be destroyed are ones nothing references — which is exactly the case where cascade is safe. This codebase's instinct is to hold deletes (P3A-1, PLN-5, PLN-6), and that instinct is honoured by the *refusal*, not by keeping debris.

```gherkin
Feature: A deleted map takes its content with it

  Scenario: Cascade removes the map's own rows
    Given a journey map with 6 stages, 4 lenses and 24 cells
    And nothing depends on the map
    When the map is deleted
    Then its 6 stages are gone
    And its 4 lenses are gone
    And its 24 cells are gone
    And its journey_stage_owner and journey_lens_planned_work rows are gone
    And its journey_map_version rows are STILL THERE

  Scenario: Another map's content is untouched
    Given two maps in the same architecture
    When one is deleted
    Then the other map's stages, lenses and cells are all intact

  Scenario: Links pointing at the deleted map go too
    Given a cell on map A links to map B
    When map B is deleted
    Then the link row is gone
    And map A's cell is still there

  Scenario: Dangling parent and clone pointers are cleared
    Given map C has parent_map_id pointing at map B
    When map B is deleted
    Then map C's parent_map_id is cleared, not left pointing at nothing

  Scenario: The whole thing is one transaction
    Given a map delete that fails partway through
    Then nothing is deleted
    And the map is exactly as it was
```

**Counter-measures**

| Risk | Counter-measure |
|---|---|
| **A cascade destroys content someone wanted** | US-DEL-1-01 ships **first** and must be live before this story starts, so only unreferenced maps can reach the cascade at all. The UI confirm is also updated to say what will be deleted, with counts: *"This will delete 6 stages, 4 lenses and 24 cells. This cannot be undone."* |
| `db.del` with a non-unique field only removes the first match (CLAUDE.md) | Every child is queried first and deleted **by its own id**, inside a `db.transaction` — the shape `planner/delete_timeline_cascade` already uses. |
| A half-run cascade leaves a map with some content gone | One `db.transaction` around the whole thing, as above. |
| A new child table is added later and nobody updates the cascade | The orphan audit from US-DEL-1-04 becomes a **standing test**, not a one-off: it fails if any table gains rows whose parent map is missing. |

---

### US-DEL-1-04 — Clean up the orphans that already exist

> **As the only support person,
> I want** the ~719 rows belonging to maps nobody can see cleared out,
> **so that** the database says what is true and future audits aren't chasing ghosts.

**⏸ Needs the founder's explicit approval before any row is deleted (CLAUDE.md).** Nothing in this story runs without a go.

```gherkin
Feature: One-off orphan cleanup

  Scenario: Dry run first, always
    When the cleanup is run in report mode
    Then it lists every orphan row it would delete, by table, with counts
    And it deletes nothing
    And the counts match the audit that found them

  Scenario: Versions are never in scope
    When the cleanup runs in any mode
    Then no journey_map_version row is listed or deleted
    And the report says plainly why they are excluded

  Scenario: Plan and template links are repaired, not just deleted
    Given a plan points at a deleted map
    When the cleanup runs
    Then the dead planner_workspace_map link is removed
    And the plan itself is untouched
    And an event records which plan lost which link

  Scenario: Live data is unaffected
    Given 24 live maps with their content
    When the cleanup runs
    Then every live map still has exactly the stages, lenses and cells it had before
```

**Counter-measures**

| Risk | Counter-measure |
|---|---|
| **The cleanup deletes something live** | Dry-run report first, reviewed by the founder, and the before/after count of every LIVE map's children is asserted equal. Run on a clone first, per CLAUDE.md. |
| It removes the versions currently protecting Execution | Versions are excluded by the allow-list and the exclusion is tested, not just intended. |
| It reports success while deleting nothing (the OBS-1 heartbeat failure) | The count of rows deleted is re-read from the database afterwards and compared with what was reported. **A function's own counter is not evidence.** |
| A plan silently loses a map it was using | Each repaired link is logged with the plan name, and the summary names them so the founder can re-attach if the map was deleted by mistake. |

---

### US-DEL-1-05 — Delete permission matches who can see the map

> **As a** teammate on a shared account,
> **I want** the Delete control to appear only when I can actually delete,
> **so that** I'm not offered an action that always fails.

Introduced by O8 on 2026-10-17: the map list became account-scoped, so you now see maps a teammate owns — but `DELETE journey_map` and `DELETE journey_architecture` still check `owner_user == auth.id`. The button is shown on maps that will refuse.

**Error code:** `E-DEL-002` — *"Only the person who created this map can delete it."*
(Replaces the current bare `Access denied`, which doesn't say who can.)

```gherkin
Feature: Delete is offered only where it is allowed

  Scenario: I see a teammate's map
    Given a map owned by another person on my account
    When I open the map list
    Then the map is listed
    And no Delete control is offered for it

  Scenario: I try anyway
    Given a map owned by another person on my account
    When I send a delete for it
    Then it is refused with E-DEL-002
    And the message says who can delete it

  Scenario: My own map
    Given a map I own, that nothing depends on
    Then the Delete control is offered
    And deleting it works

  Scenario: An admin
    Given I am an account admin
    Then I may delete any map on the account
    And the same dependency rules in US-DEL-1-01 still apply to me
```

**Counter-measures**

| Risk | Counter-measure |
|---|---|
| Hiding the button is mistaken for enforcement | The server check stays and is the real rule; the UI only avoids offering what will fail. Both are tested. |
| The rule is written backwards and hides Delete from everyone | An E2E asserts the owner **does** still see and use it — the same guard E2E-W9-01 uses for the Agents screen. |
| Admin override is assumed but never specified | Stated explicitly above: admin may delete any map on the account, and is still bound by US-DEL-1-01. |

---

## Build order

1. **US-DEL-1-01** — stops the bleeding. Nothing else should ship first.
2. **US-DEL-1-02** — a comment and a guard; makes the accidental safety deliberate.
3. **US-DEL-1-05** — small, and removes an edge introduced on 2026-10-17.
4. **US-DEL-1-03** — only after 01 is live. Needs the A/B decision.
5. **US-DEL-1-04** — needs explicit approval; run on a clone first.

## Governance

- **Tables:** no new tables, no schema changes. `journey_map_version` joins GOV-1's `appendOnly` manifest.
- **Validation & messages:** `E-DEL-001` and `E-DEL-002`, both added to `errorCatalog.json` with `what_happened`, `likely_cause` and `fix_hint`. Both are complete literals, so the error-code registry guard checks them exactly.
- **Events:** every refusal logs `outcome: "rejected"` with its code; every successful delete logs a success event with the counts of what went with it; the orphan cleanup logs a summary at `warn`.
- **Shared rules live in one function:** `journey/assert_map_unused` is called by the map delete and the architecture cascade. Neither holds its own copy.

## Test Plan

| ID | Type | What |
|---|---|---|
| UT-DEL-1-01 | Unit | `assert_map_unused` returns the right reason for plan / template / job dependencies |
| UT-DEL-1-02 | Unit | The cascade allow-list excludes `journey_map_version` |
| FT-DEL-1-01 | Functional (live) | Delete a map used by a plan → `E-DEL-001` naming the plan |
| FT-DEL-1-02 | Functional (live) | Delete an unused map → gone, with its stages/lenses/cells, versions intact |
| FT-DEL-1-03 | Functional (live) | Delete an architecture → versions intact, no new orphans |
| FT-DEL-1-04 | Functional (live) | A job pinned to a deleted map's version still returns full instructions |
| FT-DEL-1-05 | Functional (live) | Non-owner delete → `E-DEL-002` |
| GUARD-DEL-1-01 | Guard | No `db.del` against `journey_map_version` anywhere in `apis/` or `functions/` |
| GUARD-DEL-1-02 | Guard | Standing orphan audit: zero rows whose parent map is missing |
| E2E-DEL-1-01 | Playwright | Delete control is offered on an owned map and absent on a teammate's |

**Completion gate:** all of the above green, the standing orphan audit reporting zero, and `npm test` plus the existing planner/performer specs unaffected.

## Model guidance

**Opus** for US-DEL-1-03 and US-DEL-1-04 — cascade logic and a destructive one-off cleanup are exactly the "risky parts" CLAUDE.md reserves Opus for. **Sonnet** is fine for 01, 02 and 05.

## Test Results

*(to be filled in as stories are built)*
