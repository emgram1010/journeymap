# DEL-2 — Archive (SOFT delete): hide it, stop new work, bring it back any time

**Epic ID:** DEL-2
**Kind of delete:** 🟡 **SOFT.** Nothing is removed from the database. Everything can be restored.
**Status:** 📋 Written, not built (2026-11-20).
**Depends on:** DEL-1 (Epic-6, done), COP-2 approval levels, COP-11 "force wait" (`act_force_wait`, built 2026-11-19).
**Raised by:** founder, 2026-11-20. A test map with 7 jobs could not be removed or even hidden, because today the soft delete is refused whenever a map has jobs.
**Read first:** `README.md` in this folder. It holds the safety rules and what to tell the founder before you start.

---

## 1. Goal

Archive is the normal way to remove something. It hides the item, stops new work on it, never
breaks work that already exists, and one press brings it back. A person can always archive. The
AI agent can archive without asking, except when work is in progress.

The examples in this epic (a map, a business, a plan) show the pattern. Build the pattern once and
apply it to each kind of item; do not build three separate versions.

## 2. Decisions already made by the founder (2026-11-20)

| # | Decision |
|---|---|
| D-1 | Archive (soft) is the normal delete. Hard delete is rare and is its own epic (DEL-3). |
| D-2 | The AI agent may archive **without asking first**. It runs, then tells the owner, with an Undo. |
| D-3 | Exception: when the item has **work in progress**, the agent stops and asks. A person sees a warning and may confirm. |
| D-4 | When an item with work in progress is archived, that work **finishes normally**. No new work can start. |
| D-5 | While something is archived, **no AI agent reads it or uses its knowledge**. Enforced by the server (story 09). |

## 3. What exists today

Checked in the repo files on 2026-11-20. **Live Xano was not compared; story 01 does that.**

| Fact | Where |
|---|---|
| Deleting a business is soft by default: it writes a marker for the business and for every map inside. `hard: true` is needed to destroy anything | `apis/journey_map/69_journey_architecture_journey_architecture_id_DELETE.xs` |
| **The gap:** that soft delete is refused if any map inside is used by a plan, a template, or has jobs (E-DEL-001). So an item with history cannot even be hidden | same file, `journey/assert_map_unused` |
| Marker table for maps exists | `static/tables/131_journey_map_deleted.xs`, `functions/journey/deleted_map_ids.xs` |
| The business delete's comments mention a restore endpoint. **No local file for it was found** | to verify in story 01 |
| The local file for the single-map delete (api 22) does not mention the marker table. Local may be behind live | to verify in story 01 |
| A plan can be archived and restored (`is_archived`). There is no plan delete | `apis/planner/527_workspace_workspace_id_archive_POST.xs` |
| Archiving a plan does not free its maps: the plan link still counts as "in use" | `journey/assert_map_unused` reads `planner_workspace_map` only |
| Jobs read a frozen copy of the map (`journey_map_version`), never the live map. This is why archiving cannot break running work | DEL-1, US-DEL-1-02 |
| The copilot's own playbook business can never be deleted (E-COP-073) | api 69 |
| The approval gate can force an action to wait for the owner | `functions/copilot/action_gate.xs` (`act_force_wait`) |
| Playbook entries already have their own soft delete ("retire") with Undo | `functions/copilot/skill_write.xs` |

## 4. Rule

**Archiving hides and freezes. It never removes. Work that exists keeps running; new work is
refused; Restore brings everything back untouched.**

## 5. Do not break

- `journey_map_version` is permanent. Nothing here deletes or changes one.
- No table in `historyTables.ts` gets a `db.del`. The guard test stays as it is.
- Existing markers and `is_archived` are reused. Do not add a second way to mark something archived.
- The copilot's own business and locked playbook entries stay protected.

## 6. Non-goals

- Removing anything from the database (that is DEL-3).
- Taking a map out of a plan without archiving (open item O10 from DEL-1).
- Auto-archiving on a timer.

---

## 7. Stories

### US-DEL-2-01 — Know what is really live (read-only)

**As** the builder **I want** a checked list of every soft-delete piece that exists live **so that** I extend it and do not build a duplicate.

```gherkin
Scenario: inventory before any change
  Given the local files and the live workspace may differ
  When I fetch the live source of api 22, api 69, any restore endpoint, the marker tables and api 527
  Then I record, for each, whether it exists live, whether local matches, and what it does
  And I change nothing
  And I tell the founder what I found before building story 02
```

Counter-measure: no push happens in this story. If local and live differ, stop and ask which is right.

### US-DEL-2-02 — One check that says what an archive touches

**As** the owner **I want** to see what depends on an item before I archive it **so that** nothing surprises me.

```gherkin
Scenario: the impact of archiving
  Given an item (a map, a business or a plan)
  When anyone asks to archive it
  Then one shared function returns: jobs in progress, jobs finished, plans using it, templates using it, scheduled runs pointing at it
  And "work in progress" means at least one job or task that is in_progress or blocked, or scheduled for today or later
  And the function only reports; it never refuses and never writes
```

- ONE function (suggested `archive/impact`), called by the screen, the endpoints and the AI tool. No second copy of the rule.
- Counting queries only (`return = {type: "count"}`), like `journey/assert_map_unused`.

### US-DEL-2-03 — A person can always archive

**As** the owner **I want** archive to work even when the item has history **so that** I can clear away tests and old work.

```gherkin
Scenario: archive an item with finished jobs
  Given a map with 7 finished jobs
  When I press Archive and confirm
  Then the map is marked archived and leaves my lists
  And its jobs, versions and logs are untouched

Scenario: archive an item with work in progress
  Given a map with 3 jobs in progress
  When I press Archive
  Then I see "3 jobs are in progress. They will finish normally. No new work can start."
  And the item is archived only after I confirm

Scenario: archive a business
  When I archive a business
  Then every map inside is archived with it, in one transaction
  And either all of it is archived or none of it
```

- Change: `journey/assert_map_unused` keeps blocking the **hard** path only. The soft path uses story 02's report instead of a refusal.
- Permission stays as DEL-1-05: the owner of the item or an account admin.

### US-DEL-2-04 — An archived item accepts no new work

**As** the owner **I want** the server to refuse new work on archived things **so that** nothing half-hidden keeps growing.

```gherkin
Scenario Outline: new work is refused
  Given an archived <item>
  When someone tries to <action>
  Then the server refuses with a plain message naming the item and saying "Restore it first" (E-DEL-003)
  And a "rejected" event is logged
  And the person's typing is kept on the screen

  Examples:
    | item     | action                               |
    | map      | create a job from it                 |
    | map      | add it to a plan or a template       |
    | map      | publish a new version of it          |
    | plan     | add a job, a person or a time window |
    | business | create a map in it                   |

Scenario: existing work continues
  Given a job in progress whose map was archived
  When a performer starts, finishes or blocks a task
  Then it works exactly as before
```

- ONE guard function (suggested `archive/assert_active`), called by every write path above. The UI may hide buttons, but the server always checks again.
- Scheduled copilot runs skip archived businesses and say so in their log.

### US-DEL-2-05 — Restore brings it back untouched

**As** the owner **I want** one Restore **so that** an archive is never a loss.

```gherkin
Scenario: restore a map
  Given an archived map
  When I open "Archived" and press Restore
  Then it is back in my lists exactly as it was
  And a "restored" event is logged

Scenario: restore a map whose business is archived
  When I press Restore on the map
  Then I am told to restore the business first (E-DEL-004)

Scenario: restore a business
  Then the maps that were archived WITH it come back
  And a map archived on its own, before the business, stays archived
```

- Each list (maps, businesses, plans) gets an "Archived" filter with a Restore button.
- The marker records who archived, when, why, and whether it was archived on its own or with its parent.

### US-DEL-2-06 — "Delete" on a plan means archive

**As** the owner **I want** the plan screen to offer Archive **so that** I stop looking for a delete that does not exist.

```gherkin
Scenario: archive a plan
  When I press Archive on a plan and confirm
  Then the plan leaves the default list and accepts no edits (already true today)
  And its maps are no longer counted as "in use" by that plan for another archive
  And Restore brings the plan back with every link intact
```

- The plan link row is kept. The in-use check learns to ignore links from archived plans.

### US-DEL-2-07 — The AI agent archives without asking, and stops when work is in progress

**As** the owner **I want** the agent to tidy up by itself **so that** I am not asked about every small archive, but I am asked when it matters.

```gherkin
Scenario: the agent archives an idle item
  Given an item with no work in progress
  When the agent calls the archive tool
  Then the item is archived at once
  And the owner is told what was archived and what it touched, with an Undo

Scenario: the agent meets work in progress
  Given an item with work in progress
  When the agent calls the archive tool
  Then nothing is archived
  And an approval request waits for the owner, listing the work in progress (E-COP-020)
  And if the owner approves, the agent re-sends and the item is archived

Scenario Outline: things the agent can never archive
  When the agent tries to archive <thing>
  Then it is refused with <code>, at every approval level

  Examples:
    | thing                              | code      |
    | the copilot's own playbook business | E-COP-073 |
    | a locked playbook entry (retire)    | E-COP-089 |
    | an item in another account          | E-COP-002 |

Scenario: the agent restores
  When the agent calls the restore tool
  Then the item is restored and the owner is told
```

- New action type `archive_item` in `copilot/action_types`: reversible, default level **"tell"** (runs, then tells you). The owner can tighten it to "wait" on the levels screen.
- Work in progress sets `act_force_wait`, so it waits at every level. Forcing can only make it wait.
- Two tools, `archive_item` and `restore_item`, through the normal gate (ticket, daily cap, audit row).
- The approval carries the impact counts it was based on. If the counts changed by approval time, the agent asks again (the COP-11 version rule, same shape).
- **The agent has no hard-delete tool.** That is DEL-3 and it is person-only.

### US-DEL-2-08 — Health shows every archive and restore

**As** the support person **I want** archives on the Health page **so that** "where did my map go?" has an answer.

```gherkin
Scenario: an archive is visible
  When anything is archived, restored or refused
  Then one event is logged with who (person or agent), what, the impact counts and the reason
  And Health lists the last 30 days of archives with a Restore link
```

- Extends `event_log`. No second log.

### US-DEL-2-09 — The AI agents do not read or learn from archived things

**As** the owner **I want** archived maps and businesses to be invisible to every AI agent **so that** old or test content never shapes its answers, plans or playbook.

Added by the founder on 2026-11-20. **This is enforced by the server, not only by telling the AI.**
An instruction can be ignored; a tool that returns nothing cannot.

```gherkin
Scenario Outline: read tools leave archived content out
  Given an archived <item>
  When any AI agent calls <tool>
  Then the archived item is not in the result

  Examples:
    | item     | tool                                              |
    | map      | list_maps, search_maps                            |
    | business | list of businesses, list_maps for that business   |
    | plan     | the planner read tools                            |

Scenario: the agent asks for an archived item by its id
  Given an archived map
  When an AI agent calls get_map, get_slice, get_gaps or any read tool with that map's id
  Then it gets no content, only: "This is archived. Ignore it unless the owner restores it." (E-DEL-003)
  And the refusal is logged as "rejected"

Scenario: the context the server builds for the agent
  Given a chat or a scheduled run
  When the server loads the business, goals, notes, maps and playbook into the agent's context
  Then nothing from an archived map or business is included
  And a scheduled run skips an archived business entirely

Scenario: the playbook
  Given a playbook entry scoped to a map or business that is now archived
  Then it is not loaded into the agent's context while that item is archived
  And it loads again after Restore

Scenario: search and compare
  Then archived maps are left out of map search, scenario compare and leakage tools
  And the search summary of a map is hidden while it is archived

Scenario: the agent is told why
  Given the owner asks the agent about an archived item by name
  Then the agent says it is archived and offers to restore it (story 07), and does not answer from its content

Scenario: every agent and every door
  Then this holds for the copilot, the strong copy, the map chat agent, the builder, the orchestrator, the researcher, the compare analyst
  And for an outside Claude on the MCP door, signed in as a person
```

- ONE rule: the same visibility function the lists use (`journey/visible_map_ids`), applied inside the tool gate or each read tool, so a new tool cannot forget it. A source-reading test lists every tool under `ai/tool/` that takes a map, business or plan id and checks each one calls the rule.
- One line is added to each agent's instructions: "Archived items are not available to you. Do not use anything you remember about them." This is a helper, not the protection.
- Earlier chat history may still mention an archived item. The context builder adds a note naming the items archived since, with "disregard what was said about these".
- **A person on the outside MCP door** gets the same result as the agent: archived items are hidden there too. A person sees archived items in the app's "Archived" view, not through AI tools.
- Restore makes everything readable again at once; nothing is re-indexed by hand.

---

## 8. Governance

| Area | Rule |
|---|---|
| Tables | Reuse `journey_map_deleted`, `journey_architecture_deleted`, `planner_workspace.is_archived`. Any new field is additive, on a side table if the parent has trimmed text columns (CLAUDE.md). Ask before any schema push. |
| Delete behaviour | No `db.del` in this epic except removing a marker row on Restore. |
| Validation | Server refuses new work on archived items with friendly messages; typing is kept. |
| Error codes (proposed; check the catalog for free numbers first) | `E-DEL-003` archived, restore it first. `E-DEL-004` restore refused, parent is archived. |
| Events | `archived`, `restored`, `archive_rejected`, `archive_waiting` with counts in metadata. |
| Rollback | Every story is additive. Git HEAD holds the old files. A flag per account switches the "soft path ignores in-use" change off. |

## 9. Counter-measures

| Risk | Counter-measure |
|---|---|
| Archiving breaks running work | Jobs read frozen versions. Story 04 has a test that a job on an archived map still starts and finishes. |
| An archived item still shows somewhere, half-hidden | One function decides visibility (`journey/visible_map_ids`). A test lists every list endpoint and checks each one uses it. |
| An AI agent still answers from an archived map | Read tools return nothing for it (server rule, story 09); a real-AI test asks about an archived fixture and checks the reply uses none of its content. |
| A new AI tool forgets the archive rule | The rule sits in one function; a test fails for any tool that takes a map, business or plan id and does not call it. |
| The agent archives the wrong thing | Runs then tells with Undo; work in progress always waits; daily cap applies; every archive is on Health. |
| Restore brings back less than was archived | The marker records what went with what; a test archives and restores a business and compares row counts before and after. |
| Two archives at the same moment | The marker table has a unique index on the item id. A second insert fails cleanly. |
| A multi-row write half-applies | Query, then loop by id inside `db.transaction` (CLAUDE.md: `db.patch` and `db.del` touch only the first match). |

## 10. Test plan

| Layer | Tests |
|---|---|
| Unit (source-reading) | One impact function, one guard function, each write path calls the guard, no `db.del` on history tables, action type is "tell" and reversible, force-wait on work in progress |
| Functional (live, test account 13 only) | Each Gherkin scenario above through real HTTP, on fixtures made for the test |
| Real AI | The agent archives an idle fixture; meets work in progress and waits; is refused the playbook business; is asked about an archived fixture and uses none of its content, then reads it again after Restore |
| UI (Playwright) | Archive with impact message, Archived filter, Restore, refused new work keeps typing |
| Regression | `npm test`, `workflow_tests/1–12`, existing Playwright specs |

## 11. Model guidance

Opus 5.5 for stories 03, 04, 07 and 09 (guards, the approval gate and every AI read path), with a review pass after. Sonnet 5.5 for 02, 05, 06, 08 and the screens. Haiku 5.5 for fixtures.

## 12. Test results

*(Empty. Filled in as each story is built.)*
