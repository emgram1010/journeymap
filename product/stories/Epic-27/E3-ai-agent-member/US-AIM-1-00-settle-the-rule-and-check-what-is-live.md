# US-AIM-1-00 — Settle the rule and check what is live (read-only)

**Epic:** AIM-1 · **Size:** S · **Model:** Opus 5.5 · **Status:** 📋 Not started
**Decision D-3:** ✅ approved by the founder 2026-11-21: "May an AI member hold its own login,
marked as AI, with less power than a person?" — yes. It reads, writes drafts and logs its own
steps; it never publishes, deletes, approves or changes permissions.
**Left in this story:** the PRD §10 and USR-3 amendment notes (ask before editing those files)
and the read-only inventory. **No push happens in this story.**

## Description

Two earlier epics already cover part of this ground, and one of them says the opposite of what
this epic asks for. USR-3 says an AI agent holds no grant and is out of scope. COP-1 already
gave the copilot an identity, a gate, a token check, an off switch and a cap. If this epic is
built without reading those, the result is two identity systems and a broken rule nobody
decided to break. This story gets the decision and the facts first.

## User story

**As** the owner, **I want** the builder to confirm the new rule with me and list what already
exists, **so that** AI members extend what is built and nothing I decided earlier is undone by accident.

## Acceptance criteria

```gherkin
Scenario: the decision
  Given USR-3 says an AI agent holds no grant
  When the builder asks one short question: "May an AI member hold its own login, marked as AI, with less power than a person?"
  Then my answer is recorded in the PRD's settled decisions and in USR-3 as an amendment note
  And no code is written until I answer

Scenario: the inventory
  When the builder fetches the live source of the items below
  Then for each one it records: exists live (yes/no), matches the local file (yes/no), what it does
  And it changes nothing

Scenario: local and live differ
  Then the builder stops and asks which is right
```

**Inventory list (fetch live, compare to local):**

1. `planner_agent`, `agent_profile`, `user` and whatever marks a user as "AI" on Manage users (COP-1 story 06).
2. `journey/tool_gate`, `usr/mcp_caller`, `usr/assert_module_access`, `planner/resolve_actor`.
3. The add-member endpoint (PLN-5) and its checks: does it already accept `kind: "ai"`?
4. How user 34 and member 155 are stored today, and how user 34 signs in.
5. `activity_log`: does a row store the performer's **name**, or only an id? (Story 02 depends on this.)
6. Endpoint 563 and `log/next_status`: which checks sit in the endpoint and which in the function.
7. How "live day" is stored and checked (LIVE-1, REPUB-1).
8. How a token for the outside door is issued, stored and revoked today.

**Output:** a short table added to `epic.md` section 2, and a list of what each later story
reuses versus adds.

## Counter-measures

| Risk | Prevention |
|---|---|
| The builder reads a short reply as approval to build | The decision is asked as one question; a "yes" covers the rule only, not a push |
| The inventory quietly fixes something | Read-only tools only: `getTableSchema`, `getFunction`, `getAPI`, `getTool` |
| Editing USR-3 without being asked | The amendment note is proposed in chat; the file is edited only on the founder's yes |
| A later story builds on a guess | Any "Assumed" item in stories 01–04 that this inventory disproves is corrected in that story's file before it is built |

## Governance

Nothing is written, so no events. The decision and the date go in PRD §10.

## Tests

None. The gate for this story is the founder's recorded answer and the inventory table.
