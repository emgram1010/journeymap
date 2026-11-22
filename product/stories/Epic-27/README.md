# Epic-27 — START HERE. AI members, on-demand work, and safer tools

**Status (2026-11-21):** E1, E2, E5, E6 ✅ built and verified live. E3 🟡 core built (guardrails, tokens, off switches). E4 🟡 order intake built; live-day placement, webhook and polling not built. Each epic's Test Results lists what was not built or not run.
**Raised by:** founder, 2026-11-21 ("Emgram: fleshed-out features", six backend epics).
**Hardened by:** Fable 5.2, same day, against the repo files. **Live Xano was not compared.**
Every epic starts with a read-only story or check that does that.

---

## 1. What is in this folder

| Folder | Epic | ID | Size | Model |
|---|---|---|---|---|
| `E1-data-safety/` | Data-safety fixes | SAFE-1 | S | **Opus 5.5** (founder, 2026-11-21) |
| `E2-plan-discovery/` | Plan discovery in the connector | DISC-1 | S | Sonnet 5.5 |
| `E3-ai-agent-member/` | AI agent membership and execution, with the AI-as-employee security model (section 4a, stories 05–09) | AIM-1 | XL | **Opus 5.5**, then an Opus review |
| `E4-on-demand-jobs/` | On-demand jobs and the order webhook | DEMAND-1 | L | **Opus 5.5** for story 01; Sonnet for the rest; Opus review |
| `E5-item-scaled-durations/` | Item-scaled durations | SCALE-1 | M (likely smaller, see below) | Sonnet 5.5, then an Opus review |
| `E6-map-tags/` | Map tags and filtering | TAG-1 | M | Sonnet 5.5 |

Each folder holds `epic.md` and one file per story (`US-<ID>-<nn>-<name>.md`).

**Build order:** E1 → E2 → E3 → E4 → E5. E6 can run in parallel at any point.

## 2. What the hardening pass found (read this before building)

These are the differences between the request as written and what the repo shows.

| # | Finding | Where it is handled |
|---|---|---|
| F-1 | **The cell bug runs both ways.** `update_cell` writes `$input.content ?? $cell.content`. An omitted text input is `""` and `??` only catches a real `null`, so a times-only update writes `""` over the text. By the same rule a **text-only** update very likely writes `0` over all four time fields. | SAFE-1 story 01 |
| F-2 | `fill_cells` reads each update from a JSON list, so a left-out key is a real null and is kept. It is safer than `update_cell`, but it cannot tell "left out" from "sent as null", and it holds its own copy of the rule. | SAFE-1 story 02 |
| F-3 | **E3 contradicts a settled rule.** USR-3 says: "An AI agent is not a person, holds no grant, and is out of scope", and `activity_log.performer_user_id` is documented as "0 for system or AI". E3 gives an AI its own login, grants and log rows. The founder must confirm this replaces that rule. | AIM-1 story 00 |
| F-4 | **Part of E3 already exists.** COP-1 gave the copilot an identity, a gate every tool passes (`journey/tool_gate`), an off switch, a daily cap, and a token check for the outside door (`usr/mcp_caller`). E3 must extend these, not build a second identity system. | AIM-1 stories 00, 03 |
| F-5 | **Most of E5 already exists.** `work_item_line` (table 139), the lines endpoints (607, 608), `functions/estimate/compute_estimate.xs`, published rates (`stage_rate`, table 138) and the Items row (ITEM-1). `plan_add_job` passes no lines, which may be the whole reason an order planned 11 hours. | SCALE-1 story 00 |
| F-6 | **E4's webhook has no routing rule.** An order arrives with a number, dates and items. Nothing says which plan, which map, which member and which date it becomes. Without that rule story 03 cannot be built. | DEMAND-1 story 03, decision D-2 |
| F-7 | **"The same request twice" needs a database rule, not a check.** Two overlapping requests both pass a "does it exist?" check (proven live in EXC-1). Only a unique index stops a double. | DEMAND-1 story 01 |
| F-8 | **"Today" depends on the time zone.** A booking at 8 pm Central is already tomorrow in UTC. Every date rule in E4 must use the business's time zone. | DEMAND-1 stories 01, 04 |
| F-9 | A scheduled task can fail silently for hours (OBS-1 heartbeat ran 8 hours writing nothing). The polling task must record a heartbeat every run. | DEMAND-1 story 04 |
| F-10 | `planner_agent` has a unique index on (plan, name). "Update the name on rename" could collide with it. Reading the name at display time avoids the problem. | AIM-1 story 02 |
| F-11 | 7:00 am to 11:00 pm every 15 minutes is **65** runs if both ends run, not 64. Harmless, but the tests should not assert 64. | DEMAND-1 story 04 |

## 3. Decisions (founder answers 2026-11-21)

| # | Decision | Needed by | Status | Answer |
|---|---|---|---|---|
| D-1 | Reset link lifetime | SAFE-1 story 03 | ✅ Approved 2026-11-21 | **1 hour, single use** |
| D-2 | Who may reset another member's password? | SAFE-1 story 03 | ✅ Approved | **Any team admin** (not only the owner) |
| D-3 | May an AI member hold its own login, replacing USR-3's "AI holds no grant"? | AIM-1 story 00 | ✅ Approved | Yes. AI logins are marked as AI; they read, write drafts and log their own steps; they never publish, delete, approve or change permissions |
| D-4 | Do AI tokens expire? | AIM-1 story 03 | ✅ Taken by the builder 2026-11-21 (founder: "make the calls") | **90 days.** The 7-day warning is not built |
| D-11 | May an order be added to a day that has already started? | DEMAND-1 story 01 | ⏸ **Founder's call** | Not built: it overrides E-LIVE-007. Until decided, an order becomes a backlog job. Recommended: append-only republish, on Opus |
| D-5 | Routing rule: which plan, map, member and date an order becomes | DEMAND-1 story 03 | ✅ Approved | A small routing table the owner fills once; unmatched orders are listed on the Health page and nothing is added |
| D-6 | An order changed or cancelled after work started | DEMAND-1 story 03 | ✅ Approved (shape to confirm) | Never change started work. Show "order changed" / "order cancelled" in **both Planning and Execution**. Built as a **flag beside the status**, because the five step statuses are fixed by design (recommended; founder did not object) |
| D-7 | Approval level for adding work to a live day | DEMAND-1 story 01 | ✅ Approved | "Runs, then tells you" |
| D-9 | Who resets whom | SAFE-1 story 03 | ✅ Approved | Admins reset members; only the owner resets admins; platform support resets the owner |
| D-10 | Emgram had no owner role | SAFE-1 story 03 | ✅ Founder, 2026-11-21 | **Add an owner role, first owner Jav.** Built: table `account_owner` (167), seeded account 2 → user 2; lookup `usr/account_rank` (416). Set by hand only, like `is_platform_admin` |
| D-8 | Email | All | ✅ Founder, 2026-11-21 | **No email for now.** Every "notify" or "send" in this folder means an in-app notice (the person's notice list and the Health page), never an email. Reset links are handed over by the admin, not mailed |

**Done 2026-11-21:** D-3's amendment notes were added to PRD §10 (D-47) and to USR-3.

## 4. Rules for building anything in this folder

On top of CLAUDE.md, not instead of it.

1. **One epic per session.** Tell the founder the model for that epic before writing code.
2. **Verify live first.** Local files may be behind live. If they differ, stop and ask.
3. **Tests first**, then code. Run the new tests and the existing suites.
4. **Ask before** every Xano push, every schema change, every delete, every outward action (registering a webhook is outward).
5. **Additive only.** New tables or side tables. No `updateTableSchema` on a table with trim or lower filters (it drops them).
6. **One rule, one place.** If a reader and a writer need the same rule, it goes in one function.
7. **Never fail silently.** Every important step writes a success or failure event.
8. **Test data:** plan 146 "Blooming — item turnaround test", plan 147 "Blooming — strategy build", AI member "Eli Claude" (member 155, login user 34). Never test on map 178 or its business.
9. **Examples are illustrations.** Booqable is the first order source, not the only one. Name tables and fields for the pattern (`source_system`, `external_id`), never for one vendor.

## 5. What "hardened" means in these files

Every story has: a description (the pain and what exists today), a user story (As a / I want / so that),
acceptance criteria in Gherkin, counter-measures (what could break and how it is prevented),
governance (friendly errors and events) and tests. Items marked **Assumed** were not verified and
must be checked before they are built. Error codes are suggestions; register the final codes in the catalog.
