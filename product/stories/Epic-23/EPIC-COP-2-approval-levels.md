# EPIC-COP-2 — Approval levels: do this yourself, ask me for that

**Status:** ✅ Built and proven (Opus 5.5 gate + Sonnet 5.5 screens, 2026-11-15). Undo (story 04) and per-business reminder times (story 06) deferred — see Test results.
**Model:** **Opus 5.5** (or Fable 5.2) for the gate — stories 01, 02, 06, 08. Sonnet 5.5 for the
screens — stories 03, 04, 05, 07. Review pass after.
**Depends on:** COP-1 (identity, log).
**Risk:** high. A leak here sends a customer something nobody approved.
**Mock-up:** `webapp/copilot-approvals-mock/index.html` (fake data, `http://localhost:5180`).

---

## 1. Goal

**Pain:** "I don't want to approve every action." But an AI that asks for nothing is not safe, and
one that asks for everything is not useful.

**Fix:** every kind of action has one of three levels, set per business. Anything at "Waits for
you" is stored as pending and happens only when the owner approves, edits or rejects it.

**Win:** the owner's attention goes only where it matters, and the copilot earns more freedom
one action type at a time.

---

## 2. Design

```
The copilot wants to do something
        │
        ▼
   What type of action is this?  ──▶  look up its level for THIS business
        │
 ┌──────┼───────────────────────────────┐
 ▼      ▼                               ▼
Runs on its own     Runs, then tells you        Waits for you
(does it, logged)   (does it, listed for you,   (stored as pending — nothing happens
                     undo where possible)        until Approve / Edit / Reject)
```

| Level | Meaning | Typical use |
|---|---|---|
| **Runs on its own** | Done and logged | Reading, checking, drafting, internal notes |
| **Runs, then tells you** | Done, then listed under "What the copilot did" | Routine replies from approved templates |
| **Waits for you** | Not done until the owner decides | Anything reaching a customer, a booking or money |

- **Approval happens on the doing side**, right before the action — not per plan and not per map.
- **One set of levels per business.** Every plan in that business follows it.
- **The server holds the gate.** A waiting action cannot run from the copilot's side at all; only
  the approval endpoint can run it.
- **Levels move only when the owner moves them.** The copilot may suggest; it never changes one.
- **Two actions never leave "Waits for you":** Publish version and Publish to live (story 08).

---

## 3. Stories

### US-COP-2-01 — Action types and their levels
**Status:** ✅ Built (2026-11-15).

**As an** owner, **I want** each kind of action to have its own level,
**so that** I decide once per type, not once per action.

```gherkin
Scenario: A new business starts safe
  Given a business with no levels set
  Then reading and drafting run on their own
  And anything reaching a customer, a booking or money waits for me

Scenario: I change a level
  When I set an action type to "Runs, then tells you"
  Then the next action of that type follows the new level
  And actions already waiting stay waiting

Scenario: A locked type cannot be lowered
  When I try to lower a locked type
  Then it is refused with a friendly message

Scenario: An unknown action type waits
  Given the copilot attempts an action whose type has no level
  Then it is treated as "Waits for you"
```

**Build notes.** A small catalogue of action types (key, plain-language name, what it touches:
internal / customer / booking / money, reversible yes/no, locked yes/no) and a per-business level
table with a unique index on (business, action type). Every write tool declares its action type in
the same list COP-1 uses for modules. The lookup is **one function**. Default levels: decision D-8.

### US-COP-2-02 — A waiting action is stored, not done
**Status:** ✅ Built (2026-11-15).

**As an** owner, **I want** a waiting action to do nothing until I decide,
**so that** "Waits for you" is a real stop, not a suggestion.

```gherkin
Scenario: Nothing happens before approval
  Given an action type at "Waits for you"
  When the copilot attempts it
  Then a pending item is created with the exact content it wants to send or write
  And the action itself has not happened

Scenario: Approve runs exactly what I saw
  When I approve a pending item
  Then exactly the stored content is carried out, once

Scenario: Edit runs my version
  When I edit a pending item and send it
  Then my version is carried out, and the log records that I edited it

Scenario: Reject does nothing
  When I reject a pending item
  Then nothing is carried out and the copilot is told it was rejected

Scenario: Approving twice does not act twice
  When Approve is clicked twice quickly
  Then the action is carried out once

Scenario: Stale items are caught
  Given the thing a pending item would change has changed since it was drafted
  When I approve it
  Then it is refused with "this is out of date" and the copilot is asked to redraft
```

**Build notes.** A `pending action` table: business, action type, the tool and its full input as
stored JSON, a summary for the screen, status (waiting / approved / edited / rejected / expired /
failed), who decided, when. The **approval endpoint** carries out the stored input; the copilot's
own call only creates the row. Double-approve is stopped by a **unique index**, not a transaction
(CLAUDE.md, endpoint 610). Staleness: store a fingerprint of the target at draft time and compare
on approval; build the fingerprint by explicit concatenation, never `json_encode`.

### US-COP-2-03 — The approvals inbox
**Status:** ✅ Built, seen in a browser on real data (2026-11-15). **Model: Sonnet 5.5.**

**As an** owner, **I want** one screen with everything waiting for me,
**so that** I can clear it in a minute.

```gherkin
Scenario: I see what is waiting and why
  When I open Approvals
  Then each item shows what it will do, for whom, the draft, and why it is waiting
  And a count shows on the menu from every screen

Scenario: Approve, Edit, Reject
  Then each item has Approve, Edit and Reject, and my typing is kept if a save is refused

Scenario: Nothing waiting
  Given nothing is waiting
  Then the screen says so plainly
```

**Build notes.** Follow the mock-up's three tabs: Waiting for you · What the copilot did ·
Approval levels. Pure logic in a model file with tests; components thin.

### US-COP-2-04 — "Runs, then tells you", honestly
**Status:** 🟡 Built except Undo: reversible items show a disabled Undo ("arrives with the first copilot tool of this type"); irreversible show "Can't be undone". No tool of a reversible "tell" type exists yet (COP-5). **Model: Sonnet 5.5.**

```gherkin
Scenario: I can see what it did without being asked
  Given an action ran at "Runs, then tells you"
  Then it appears under "What the copilot did", marked as not yet seen

Scenario: Undo where undo is real
  Given the action can be reversed
  Then it has an Undo button, and Undo reverses it and is logged

Scenario: No false Undo
  Given the action cannot be reversed (a message already sent)
  Then it shows "Can't be undone" instead of an Undo button

Scenario: Irreversible customer-facing types are flagged when lowered
  When I set an irreversible type to "Runs, then tells you"
  Then I am told plainly it cannot be undone, and asked to confirm
```

### US-COP-2-05 — Limits inside a type
**Status:** ✅ Built (2026-11-15).

```gherkin
Scenario: Under my limit, it does not wait
  Given a money-carrying action type waits for me, with a limit I set
  When the copilot attempts one under the limit
  Then it runs at "Runs, then tells you"

Scenario: At or over the limit, it waits
  When the amount is at or over the limit
  Then it waits for me

Scenario: Limit of zero means always wait
  Given the limit is 0
  Then every action of that type waits
```

**Build notes.** One optional numeric limit per (business, action type). An optional int arrives
as `0`, never `null` — `0` is deliberately the "always wait" value, so no flag is needed here.
The amount comes from the action's stored input, validated server-side; a missing amount waits.

### US-COP-2-06 — When the owner does not answer
**Status:** ✅ Built with fixed times (remind 24 h, expire 72 h); per-business times and "the copilot says what it held" wait for scheduled runs (COP-5).

```gherkin
Scenario: A reminder, then expiry
  Given an item has waited longer than the reminder time
  Then I get one reminder
  And after the expiry time it is marked "expired" and is never carried out

Scenario: Never approved by silence
  Then no waiting item is ever carried out because time passed

Scenario: The copilot says what it held
  Given a scheduled run produced items that expired
  Then its next report lists what it held and why
```

**Build notes.** Decision D-5. Times are per business with safe defaults. A scheduled task marks
expiry; compute cutoffs into a `var` before the `where`. How the owner is told (in-app only at
first; text or email later) is an open decision in the illustration — in-app is the default.

### US-COP-2-07 — The copilot suggests, the owner decides
**Status:** ✅ Built (suggestion computed server-side; only the owner's click moves a level). **Model: Sonnet 5.5.**

```gherkin
Scenario: A suggestion after a good track record
  Given I decided 5 or more items of one type and changed 10% or fewer
  Then Approval levels suggests moving that type down one level

Scenario: Only I move it
  Then the level changes only when I click, never by itself

Scenario: Locked types are never suggested
  Then no suggestion appears for a locked type
```

### US-COP-2-08 — Publish stays human
**Status:** ✅ Built (publish_map refuses an AI caller; both publish types locked).

```gherkin
Scenario: The copilot cannot publish a map version
  When the copilot tries to "Publish version"
  Then it is refused, and it tells me the map is ready for me to publish

Scenario: The copilot cannot publish a plan to live
  When the copilot tries to "Publish to live"
  Then it is refused, and it tells me the plan is ready for me to publish

Scenario: These two cannot be lowered
  Then both show as locked on Approval levels
```

**Build notes.** Decision D-4. The existing `publish_map` tool is the first to check: it must
refuse an AI caller once COP-1's identity exists.

---

## 4. Governance

| Area | Rule |
|---|---|
| Tables | Action-type catalogue; per-business levels (unique: business + type); pending actions (unique index guarding double-approve) |
| Delete behaviour | Pending actions and their decisions are **history** — never deleted. Add to `src/ops/historyTables.ts` |
| Validation | Server re-checks the level at the moment of action, not when the draft was made |
| Error codes | `E-COP-010` waits for approval · `E-COP-011` already decided · `E-COP-012` out of date · `E-COP-013` type is locked · `E-COP-014` expired · `E-COP-015` publish needs a person. Feature `COP-2` |
| Events | Created, approved, edited, rejected, expired, failed-on-run, level changed (who, from, to) |

## 5. Counter-measures

| Risk | Counter-measure |
|---|---|
| A tool does the action *and* creates the pending row | The write lives only behind the approval endpoint; a test calls every waiting-type tool and asserts no side effect |
| A level is lowered by a bug | Level changes are written only by one endpoint that requires a signed-in person, never an AI identity |
| The owner approves something that changed | Fingerprint check at approval (story 02) |
| A flood of pending items | Daily cap from COP-1; identical waiting items for the same target are merged, not duplicated |
| The inbox count slows every page | One count query, on an indexed status column |

## 6. Test plan

| ID | Kind | What |
|---|---|---|
| UT-COP-2-01 | Unit | Level lookup: default, set, locked, unknown type, under/at/over limit, limit 0 |
| FT-COP-2-01 | HTTP | Waiting type → row created, no side effect; approve → one side effect |
| FT-COP-2-02 | HTTP | Double approve in parallel → one side effect (run 4 races, like endpoint 610) |
| FT-COP-2-03 | HTTP | Edit, reject, stale, expired paths with their codes |
| FT-COP-2-04 | HTTP | AI identity cannot change a level or publish |
| UI-COP-2-01 | Browser | Inbox on real data: approve, edit, reject; count badge; empty state |
| UI-COP-2-02 | Browser | Levels screen: change, locked, limit, suggestion |
| REG | Suites | `npm test`, `tsc`, build, COP-1 matrices |

## 7. Test results (2026-11-15, Opus 5.5)

**How it works (as built).** Every AI tool already calls `journey/tool_gate`. A tool that declares
an action type (`act_type`, plus `act_payload` / `act_summary` / `act_amount`) now also goes through
`copilot/action_gate` — **for AI identities only; people are never stopped**. One catalogue
(`copilot/action_types`), one lookup (`copilot/action_level`). "Waits for you" stores the tool and
its exact input in `copilot_action` and refuses (E-COP-020). Approving records what may run; the
copilot carries it out by calling the same tool again with `approval_id`, and the gate lets it
through **once** (unique index on `copilot_action_claim`) and **only for the approved content**.
Approval refusals are enforced whatever the report/enforce switch says.

**Pushed:** tables 146 `copilot_action_level`, 147 `copilot_action`, 148 `copilot_action_claim`,
149 `copilot_json_canon`; functions `copilot/action_types` (328), `action_level` (329),
`action_gate` (330), `canon_json` (332), `expire_waiting` (333); `journey/tool_gate` (311);
endpoints 637–642 (Members & Accounts); task 20 `copilot_expire_waiting` (hourly); tool
`publish_map` (55). Screens: `/approvals` (three tabs) + menu badge.

| Check | Result |
|---|---|
| Levels: customer message waits, unknown type waits, internal note tells, map read/draft run on their own | ✅ |
| Copilot attempts a waiting type → stored, nothing done, E-COP-020 with item number | ✅ |
| Same waiting action again → reuses the item (no duplicate) | ✅ (after fix: a json column re-orders keys; both sides now pass through `copilot/canon_json`) |
| A person attempting the same → goes straight through | ✅ |
| Copilot calls `publish_map` on its own map | ✅ refused (E-COP-025), map unchanged; its draft edit on the same map still works |
| Owner inbox / badge / member blocked from inbox and deciding | ✅ / ✅ / ✅ 403 |
| Reject; decide again (E-COP-021); map changed since draft (E-COP-022); bad decision (E-COP-032); unknown item (E-COP-029) | ✅ all |
| Edit with no content (E-COP-033) | 🔴→✅ an omitted json input arrived as `{}` and passed; fixed and re-proven |
| Edit with content → the copilot's original is refused (E-COP-027), the owner's version runs | ✅ |
| **4 parallel approves → exactly one wins** | ✅ [200, 400, 400, 400] |
| Approved item runs once (keys in a different order still match); second run E-COP-030; changed content E-COP-027; rejected item E-COP-027; wrong tool E-COP-036 | ✅ all |
| Levels: all 10 types; lowering Publish (E-COP-023); irreversible customer type without confirm (E-COP-026); bad level (E-COP-034); another account's business (E-COP-035); member blocked | ✅ all |
| Money limit 100: 50 → runs, then tells you; 100 → waits; no amount → waits | ✅ |
| Expiry: 73 h old → expired; 25 h old → one reminder; second run changes nothing | ✅ |
| Regression: list_maps / scaffold_map as a person after the gate change | ✅ |
| Browser (localhost, test admin): inbox shows item, reason, exact payload; Approve and Reject work; done list with "New" + Mark as seen; levels tab with locked / person-only / not-used-yet; COP-1 Manage users AI badge + limit | ✅ (badge refresh and plain type names fixed after the first look) |
| `npm test` / `tsc` | ✅ 804/804 / clean |

**Found live (CLAUDE.md-worthy):** a `json` column returns its keys re-ordered (by length, then
alphabetically), so a stored value never json_encodes like a fresh one — compare through
`copilot/canon_json`. An omitted optional `json` input arrives as `{}`, not null. `tool.call` is
unavailable from a function or endpoint, so an approved action is carried out by the copilot's own
re-call, not by the approve button.

**Not done / honest gaps:** no real customer/booking/money tool exists yet — the waiting path was
proven with the gate and a stand-in tool name; real tools arrive in COP-5/COP-6 and only need to
pass `act_type`. Undo has no backend (no reversible "tell" tool yet). Reminder/expiry times are
fixed. Test fixtures in account 13: copilot_action items 1–14 (all decided or expired), a money
limit row (arch 0, limit 100).
