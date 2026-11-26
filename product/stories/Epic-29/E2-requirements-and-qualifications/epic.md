# REQ-1 — What a step needs, and who holds it

**Epic ID:** REQ-1 (E2 in this folder)
**Status:** 🟡 Stories 00 to 04 built and tested live (2026-11-26). Story 05's functions are live; its change to Publish version waits for the founder's decision
**Size:** L
**Model:** Sonnet 5.5 for stories 00–04. **Opus 5.5** for story 05 (it adds to Publish version, PUB-1).
**Depends on:** nothing in this folder for the data. MATCH-1 is what uses it.
**Read first:** `../README.md`.

---

## 1. Goal

**Pain:** the planner can give any work to any active person. The system does not know that a
step needs something, or that a person has it. That knowledge lives in the planner's head.

**Win:** the person who designs the work says once what each step needs, and whether that is a
must (hard) or a preference (soft). The business records once what each person holds. From then
on the system knows.

This epic only **stores and freezes** that knowledge. Nothing is suggested, warned or refused
here; that is MATCH-1. So this epic changes no existing behaviour.

## 2. What exists today (repo and live compared 2026-11-25: planner code identical; see README F-6, F-8, F-15–F-17)

| Fact | Where |
|---|---|
| A step is a cell of the map: one stage of one row (`journey_cell`: map, stage, lens) | `static/tables/9_journey_cell.xs` |
| A job's step points at (stage key, row key) of its **pinned published version** | `static/tables/123_work_task.xs` |
| Publish version freezes the map into `journey_map_version.snapshot` with a content hash that the frontend must reproduce | `apis/journey_map/201_…publish_POST.xs`, `functions/pub/` |
| A person's lasting identity is `agent_profile` (person or AI); it holds a name, colour, daily hours and "may be put on a roster" | `static/tables/129_agent_profile.xs` |
| A person on a plan (`planner_agent`) has **no** link to their profile | `static/tables/116_planner_agent.xs` |
| An AI member's permissions are `ai_member_profile.allowed_actions`: what it may **do in the app**, not what work it is suited to | `static/tables/172_ai_member_profile.xs` |
| Nothing stores a requirement on a step or a qualification on a person | searched 2026-11-25 |
| The role registry (ROLE-1) is deferred; `method.role_id` is reserved for it | `product/stories/phase-4/EPIC-ROLE-1-…md`, table 135 |
| The feature-flag table's key is a **fixed list**; adding a key means changing a table that has a text check | `static/tables/108_account_feature_flag.xs` |

## 3. Words used in this folder

| Word | Means |
|---|---|
| **Requirement** | A named thing a person can hold. One list per account. No built-in types: a licence, a skill, a tool, a clearance and a language are all just names |
| **Needs** | A step **needs** a requirement, as **hard** (must) or **soft** (preferred) |
| **Holds** | A person **holds** a requirement, optionally until a date |
| **Fits** | A person fits a step when they hold every hard need on the day of the work (MATCH-1) |

Never "skill", "capability" or "eligible": all three already mean something else in this codebase.

## 4. Rule

**A need belongs to the definition of the work, so it lives on the map and is frozen at Publish
version. A holding belongs to the person, so it lives on their lasting profile.**

- A job reads its needs through its pinned version, like everything else about its steps.
- A version published before this epic has no needs. Its jobs behave as they do today.
- A holding with an end date stops counting **after** that date. The date that matters is the day of the work, not today.

## 5. Do not break

- The content hash of every existing published version (`pub/verify_version` passes for all of them, before and after).
- Publish version for a map with no needs produces the same hash as today.
- No column is added to `journey_cell`, `journey_map_version`, `agent_profile` or `planner_agent`.
- An AI can never record that it, or any AI, holds something.

## 6. Non-goals

- Suggesting, warning or refusing (MATCH-1).
- Roles (ROLE-1 stays deferred, D-12). A role can be added later as one more requirement.
- Levels ("senior", "level 2"). A level is a separate requirement if it is needed.
- A need that depends on **this job** rather than on the step (for example, only when the order includes a certain item). See "Keep a pulse on" in story 04.
- Proof: uploading a certificate file.

## 7. New tables (additive)

| Table | What it holds | Guard |
|---|---|---|
| `requirement` | Account, name as shown, name key (lower case), description, active | Unique (account, name key) |
| `agent_profile_requirement` | Profile, requirement, held until (optional), recorded by | Unique (profile, requirement) |
| `planner_agent_profile` | Person on a plan → their lasting profile | Unique on the person on a plan |
| `journey_cell_requirement` | Step (cell), requirement, hard or soft | Unique (cell, requirement) |
| `journey_map_version_requirement` | Version, stage key, row key, requirement, hard or soft. Written at Publish version, never edited | Unique (version, stage key, row key, requirement) |

## 8. Stories

| File | Story |
|---|---|
| `US-REQ-1-00-check-what-is-live.md` | Read-only: live vs repo, how many people cannot be linked to a profile, the ROLE-1 note |
| `US-REQ-1-01-requirement-list.md` | One list of requirements per account |
| `US-REQ-1-02-who-holds-what.md` | Record what each person holds, and until when |
| `US-REQ-1-03-link-a-person-on-a-plan-to-their-profile.md` | Every person on a plan knows their lasting profile |
| `US-REQ-1-04-what-a-step-needs.md` | Set hard and soft needs on a map step |
| `US-REQ-1-05-needs-are-frozen-at-publish-version.md` | Freeze needs with the version; one function reads a step's needs |

## 9. Completion gate

- "Forklift" and " forklift " are one requirement.
- A person holds a requirement until a date; the day after, they do not.
- Every person on a new plan is linked to a profile; unlinked people on old plans are counted and listed.
- A step has one hard and one soft need; Publish version freezes both.
- A map with no needs publishes to the same hash as before; every existing version still verifies.
- A job pinned to an older version reads no needs.
- An AI caller cannot write a holding. A second account sees nothing.
- Existing suites green. Test Results filled in.

## 10. Test Results

### Story 00 — what is live (2026-11-26, Sonnet 5.5; read-only, no row changed)

**1. Live vs repo.** Tables 9, 112, 116, 129, 130, 135 and 172 are the same live and in the repo. **Endpoint 201 (Publish version) is not:** the repo has a BRIEF-1 block (`E-BRIEF-001`, over-length task-brief text refused at publish) that is **not live**. It is uncommitted work from EPIC-BRIEF-1 (Epic-28, still in progress; it also changes `pub/canonical_hash`, `pub/build_map_snapshot` and adds `pub/brief_fields` and table 180). **Story 05 changes endpoint 201 too, so it must not be pushed until BRIEF-1's change to that same file is settled.** Stories 01 to 04 do not touch 201.

**2. People who cannot be linked to a lasting profile** (every person on every non-archived plan, per account; 95 plans, 114 people, 6 profiles in total):

| Account | People on plans | Linked through a login | Linkable by exact profile name | Not linkable |
|---|---|---|---|---|
| 2 (the founder's account) | 17 | 0 | 5 (all "Jav") | 12 (Tony, Gladys, Nick, Paris, Eli, Rochelle, across 5 plans) |
| 13 (test account) | 97 | 0 | 0 | 97 (test data) |

- **Nobody can be linked by login today.** The people with a login (Tony, Gladys, Nick, Paris, Eli, Rochelle, the test users) have **no lasting profile at all**, so there is nothing for a login to find. The one-time fill by login would link nobody.
- **Consequence for story 03 (the founder should know):** the "create a profile for this person" action is not optional. Without it, no one in the founder's account could ever hold a requirement. Story 03 gets a **Create profile** button next to "no profile": one click by an admin, from the person's name, colour and hours, with a login if they have one. It never links by name on its own.

**3. The role note (PRD §10, D-12): drafted, not written.** "Assignment is matched on needs and holdings (REQ-1, AVAIL-1, MATCH-1), not on a role. ROLE-1 stays deferred. MATCH-1 replaces SCHED-1 story 04. A role may later be added as a requirement." The PRD, ROLE-1 and SCHED-1 files are not edited until the founder says yes.

**4. The on/off switch.** Not needed by REQ-1: it stores and freezes, and changes no behaviour. MATCH-1's switch will be a row in a new small side table (the fixed key list in `account_feature_flag` is not touched).

**5. Tables.** Six, not five: `requirement` (183), `agent_profile_requirement` (184), `planner_agent_profile` (185), `journey_cell_requirement` (186), `journey_map_version_requirement` (187), plus `journey_map_version_needs_hash` (188), because the epic wants a per-version needs hash and also forbids adding a column to `journey_map_version`. Drafted in `static/tables/`; **not pushed**.

| Test | Result |
|---|---|
| T-REQ-00-1 live vs repo | ✅ done; one real difference (endpoint 201, BRIEF-1, above) |
| T-REQ-00-2 counts add up | ✅ account 2: 0 + 5 + 12 = 17; account 13: 0 + 0 + 97 = 97; total 114 |
| T-REQ-00-3 nothing changed | ✅ read-only; the one scratch function used was deleted |

## Test Results (stories 01 to 05, 2026-11-26, Sonnet 5.5)

- **Tests written first:** `requirementModel.test.ts`, 19 tests: the name rule and its limits, "held until" on the date of the work (last day counts, every empty form means no end, ends soon at 30 days), the person-link label, hard/soft and the 10-need limit, the frozen-needs canonical string and hash (pinned on both sides), and source tests for the rules that must not drift (one name function, admin-only writes, delete blocked while used, an AI cannot record a holding, freezing by plain writes inside Publish's transaction, only `req/step_needs` reads the frozen needs).
- **Built (live):** six tables (183 to 188); functions `req/*` (528 to 545: name rule, usage, guard, near matches, date rule, link, set_need, delete/copy helpers, needs hash, freeze, step_needs, job_step_needs, verify, audit); 18 endpoints (catalog group: list, add, rename, archive, delete, holders; planner group: holdings list/record/remove and person-link list/link/unlink/create-profile/fill; journey-map group: map needs, step need set/remove, apply to row); cleanup and clone changes to existing objects (remove row, remove stage, delete map, remove person, delete plan, scenario clone, template instance, repeat) and the nightly integrity task (calls `req/audit_needs`).
- **Built (app):** Catalog → Requirements tab; "What they hold" under each person in Agents; "People and their profiles" in Workspace Settings (link, create profile, clear, check all plans); "What this step needs" in the selected-step panel of the map.
- **Live tests (real HTTP, test account 13, admin and member):** `tests/req1_probe_a.py` 71 of 71 (stories 01 to 03), `req1_probe_b.py` 32 of 32 (story 04), `req1_probe_c.py` 21 of 21 (links from template and repeat, the fill, removal, clone). Story 05's functions were run on a fake version id (see below).

| Test | Result |
|---|---|
| T-REQ-01-1 add, list, rename, archive, restore | ✅ |
| T-REQ-01-2 case and spaces make one requirement | ✅ lower case, upper case with spaces, inner spaces: all "exists", nothing created |
| T-REQ-01-3 name rules and the limit | ✅ empty E-REQ-001, 61 characters E-REQ-008, HTML E-REQ-002; a lone `<` or `&` accepted. ⚠️ the 200 limit was not run live (needs 200 rows); the rule is one precondition, read in the source test |
| T-REQ-01-4 delete refused when used, allowed when unused | ✅ refused with the count while a person holds it (E-REQ-004); deleted once unused |
| T-REQ-01-5 two parallel adds leave one | ✅ four parallel adds of one name: 1 created, 3 "exists", one row in the list |
| T-REQ-01-6 archived not offered, still shown where used | ✅ |
| T-REQ-01-7 non-admin cannot write; second account sees nothing | ✅ member refused E-USR-001; another account's requirement: rename, delete and holders all "not found", and absent from the list |
| T-REQ-01-8 AI near match creates nothing | ✅ by design: a near match answers "similar" and creates nothing until the caller asks again; no AI tool exists to test |
| T-REQ-02-1 record, change the date, remove | ✅ saving twice updates; removing twice is not an error |
| T-REQ-02-2 the last day counts, the day after does not | ✅ 2027-03-31 held, 2027-04-01 not |
| T-REQ-02-3 every empty date form means no end | ✅ `""` and left out |
| T-REQ-02-4 ends soon at 30 days | ✅ 30 days yes (30 left), 31 no |
| T-REQ-02-5 archived requirement refused for a new holding | ✅ E-REQ-011; an existing holding of one can still change and shows as archived |
| T-REQ-02-6 an AI caller is refused and logged | ⚠️ not run live (no AI login set up). Covered by the source test: the endpoint calls `copilot/assert_person_only` first, the guard proved live in REPEAT-1 story 05 |
| T-REQ-02-7 other account's profile refused | ✅ record, read and link: "not found" |
| T-REQ-02-8 profile delete removes its holdings | n/a: no profile delete exists. Holdings deletion is tested through requirement and person removal |
| T-REQ-03-1 template and repeat link their people | ✅ every roster person linked to their profile; the repeat's copy carried each link |
| T-REQ-03-2 add by profile links; by hand does not | ✅ people added by hand have no link |
| T-REQ-03-3 the fill: one login one profile linked; no login listed; two profiles listed | ✅ reports first and writes nothing by default; linked on apply. ⚠️ "a login with two profiles" not run live (needs a second profile for one login) |
| T-REQ-03-4 the fill twice changes nothing | ✅ second run: 0 linked, 0 to link |
| T-REQ-03-5 a profile from another account is refused | ✅ |
| T-REQ-03-6 the people list returns the link and "no profile" | ✅ with name matches offered (one match) or only counted (two) |
| T-REQ-03-7 deleting a person or a plan removes the link | ✅ a person removed: link gone; two plans deleted: 0 left behind |
| T-REQ-03-8 existing template tests still pass | ✅ unit suites green; the template and repeat flows ran live (probe C). The older Playwright specs were not re-run |
| T-REQ-04-1 add hard, soft, switch, remove | ✅ |
| T-REQ-04-2 same need twice | ✅ "same", still exactly two on the step |
| T-REQ-04-3 whole row, count correct | ✅ the locked step skipped and named, the rest changed; counts re-read from the database; again changes nothing |
| T-REQ-04-4 row not planned work refused | ✅ E-REQ-031, single step and whole row (uses the shared `does_planned_work` rule) |
| T-REQ-04-5 archived refused; limit of 10 | ✅ E-REQ-030; 10 allowed, the 11th E-REQ-032; changing one already there still works |
| T-REQ-04-6 locked step refused | ✅ E-REQ-033, adding and removing |
| T-REQ-04-7 clone copies needs | ✅ the clone has the same need on the same step; the source keeps its own |
| T-REQ-04-8 deleting a step, row, stage, map leaves no orphan | ✅ row removed: its steps' needs gone; stage removed: gone. ⚠️ the single-cell delete endpoint (37) is not live, and the map hard delete (`delete_map_cascade`) was changed and pushed but not run live |
| T-REQ-04-9 people who hold this now, including zero | ✅ 0, then 1, and an ended holding does not count |
| T-REQ-04-10 second account refused | ✅ read, set and apply-to-row all refused |
| T-REQ-05-1 freeze hard and soft by key | ✅ `req/freeze_needs` on a fake version: 3 needs frozen by stage key and row key |
| T-REQ-05-2 a draft edit does not reach a frozen version | ✅ a need deleted from the draft afterwards: the frozen rows and their hash still verify |
| T-REQ-05-3 two versions hold different needs | ✅ 3 frozen, then 2 |
| T-REQ-05-4 a job on an older version reads the older needs | ✅ `req/step_needs` on a version with no rows answers no needs (the same answer a job on a version from before this feature gets) |
| T-REQ-05-8 hash matches the TypeScript twin; "no needs" pinned | ✅ the sample hashes to `96fede33…` on both sides; the empty set to `e3b0c442…` |
| T-REQ-05-9 build guard: only `req/step_needs` reads the frozen needs | ✅ unit test over every function and endpoint |
| Tamper evidence and the nightly audit | ✅ an extra frozen row: `count_differs`; the audit lists it and logs an E-REQ-036 failure event |
| **T-REQ-05-5, 05-6, 05-7, 05-10: Publish itself** | ⏸ **not run: the change to Publish version (endpoint 201) is written in the repo and NOT pushed.** See "Decision for the founder" below |
| Suites | ✅ `npm test` all green · `tsc` clean. Playwright and workflow tests not run |
| Browser | ✅ Requirements tab: added a requirement, a near match showed the "something like this exists" prompt and created nothing. Step panel: added a "Must have" need, it showed "No one holds this right now", removed it. Workspace Settings: "People and their profiles" with Create profile / Choose / Link |

### Decision for the founder: Publish version (endpoint 201)

- **What is built:** one call to `req/freeze_needs` inside Publish's existing transaction (next to the rate card write), and `needs_frozen` in the answer and in the success event. A map with no needs writes nothing, so its publish and hash are unchanged. Not pushed.
- **The conflict:** live Publish is MISSING the BRIEF-1 block (over-length task-brief text refused, E-BRIEF-001) that sits uncommitted in the same file. Pushing the working-copy file would also push BRIEF-1's unfinished work.
- **Recommended:** patch the LIVE Publish with the REQ-1 call only, leave BRIEF-1 for its own push, and commit only the REQ-1 lines of the file here. Then run T-REQ-05-5/6/7/10 on a clone of map 178.

### Differences from the stories

- **A sixth table** (`journey_map_version_needs_hash`) holds each version's needs hash, because the epic forbids a column on `journey_map_version`.
- **Story 03 gained "Create profile"** (one click by an admin, never by name): in the founder's account 12 of 17 people on plans had no profile, so the one-time fill by login would have linked nobody.
- **A re-link is a delete and a fresh row**, so the link table is append-only.
- **Story 02:** no screen lists "ends soon" across all people; it shows on each person and in each requirement's holders list.
- **Story 04:** "does planned work" uses the existing shared rule (`does_planned_work`), not only an explicit override.
- **The AI tool** for requirements was not built (the stories build none).

### Cleaned up

Every requirement, profile, plan, map and row the probes made was deleted (including the two throwaway fixtures for "another account"); the scratch functions were deleted. One archived plan template (id 30) and event-log rows remain. The audit test left one E-REQ-036 failure event for the fake version.

### Found, not fixed

- `DELETE journey_cell/{id}` (endpoint 37) exists only as a local file, with no sign-in check. It must never be pushed as is.
- Live Publish and the repo differ by the BRIEF-1 block (above).
