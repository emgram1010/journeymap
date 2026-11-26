# REQ-1 — What a step needs, and who holds it

**Epic ID:** REQ-1 (E2 in this folder)
**Status:** 🚧 In build (2026-11-26). Story 00 done; stories 01 to 04 next; story 05 waits on BRIEF-1
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

## Test Results (stories 01 to 05)

Not built yet.
