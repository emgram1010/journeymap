# EPIC-COP-6 — Connections library: outside systems, one business at a time

**Status:** 📋 Not started — **written for later, on purpose.** Founder, 2026-11-14: "you don't
have to do it right now, but … it's going to have to have the capability."
**Model:** **Opus 5.5** (or Fable 5.2) for story 02 (secrets). Sonnet 5.5 for the rest. Review pass after.
**Depends on:** COP-2 (levels). Nothing in COP-1 to COP-5 may be built in a way that blocks this.
**Risk:** high when built. It stores logins to other companies' systems.

---

## 1. Goal

**Pain:** a business's real data lives in other systems — a booking tool, an inbox, accounts. A
copilot that cannot reach them can only work from what someone types in.

**Fix:** a library of connections. Each business picks which ones its copilot may use. Reading is
free and logged; anything that changes the outside system follows the approval levels.

**Win:** the copilot works from real figures and can act where the work actually happens — without
one business's connections ever serving another.

---

## 2. Design

```
Connections library (per account)
  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐
  │ Booking tool │  │ Inbox        │  │ Accounts     │   ← each: name, what it can read,
  └──────┬───────┘  └──────┬───────┘  └──────────────┘     what it can change, status
         │                 │
   switched on for    switched on for
   Business A         Business A and B     ← the login is stored per business, never shared

A connection's tool is either
   READ  → runs on its own, logged
   WRITE → an action type with a level (COP-2); customer / booking / money default to "Waits for you"
```

- **General first.** The library knows nothing about any one outside system. The first connection
  (a rental-booking system, for the illustration business) is a row in it, not a special case.
- **Per business.** A connection is switched on for a business; its login belongs to that business.
- **A secret is write-only.** It can be set and replaced. It is never shown, logged or put in a map.

---

## 3. Stories

### US-COP-6-01 — A library of connections, switched on per business
**Status:** 📋 Not started.

**As an** owner, **I want** to choose which outside systems each business's copilot may use,
**so that** it reaches only what I connect.

```gherkin
Scenario: I see what could be connected and what is
  When I open Connections for a business
  Then I see each available connection, whether it is on, and when it last worked

Scenario: Off means unreachable
  Given a connection is off for this business
  When the copilot tries to use it
  Then it is refused, and it tells me the connection is not switched on

Scenario: One business's connection never serves another
  Given a connection is on for business A only
  When the copilot is working on business B
  Then it cannot use it
```

### US-COP-6-02 — Logins are stored safely
**Status:** 📋 Not started. **Opus.**

**As an** owner, **I want** an outside system's login kept where nothing can read it back,
**so that** connecting a system does not create a leak.

```gherkin
Scenario: A secret can be set but never read
  When I save a login for a connection
  Then no screen, endpoint or tool ever returns it

Scenario: A secret never appears in a log, a map or a chat
  When the connection is used
  Then the tool log, the event log, maps and chat messages contain no part of the secret

Scenario: The copilot never sees the secret
  Then the secret is attached to the outgoing request by the server, not passed through the copilot

Scenario: Replacing and removing
  When I replace or remove a login
  Then the old one stops working at once and the change is logged (without the value)
```

**Build notes.** Not verified: where Xano can hold a secret per business safely (environment
variables are per workspace, not per customer). **Spike before design.** Past incident to respect:
a `db.patch` on a JSON column merges — clearing sensitive data needs the two-step patch
(CLAUDE.md, critical block).

### US-COP-6-03 — Read is free, write follows the levels
**Status:** 📋 Not started.

```gherkin
Scenario: Reading runs on its own
  When the copilot reads from a connected system
  Then it runs without asking and is logged

Scenario: Each write is an action type
  When a connection is added
  Then each thing it can change appears on Approval levels as its own action type
  And those touching a customer, a booking or money start at "Waits for you"

Scenario: A tool with no declared kind is treated as a write that waits
  Given a connection exposes a tool not marked read or write
  Then it is treated as "Waits for you"

Scenario: What it reads is data, not instructions
  Given text in an outside record addresses the AI
  Then it changes nothing about what the copilot may do
```

**Build notes.** Reuses COP-2 entirely — no second approval mechanism. Reuses COP-4 story 03's
rule for outside text.

### US-COP-6-04 — A broken connection is visible
**Status:** 📋 Not started.

```gherkin
Scenario: The copilot says when it could not reach a system
  Given a connection is failing
  When the copilot needs it
  Then it says it could not reach it, and does not guess the data

Scenario: Health shows it
  Then Health shows which connection is failing, since when, and for which business

Scenario: A failing connection does not flood the log
  Then repeated failures are grouped, not written hundreds of times
```

### US-COP-6-05 — The first connection (spike, then build)
**Status:** 📋 Not started.

**As an** owner of the illustration business, **I want** my booking system connected first,
**so that** the copilot works from real bookings and stock.

```gherkin
Scenario: The spike answers four questions before any build
  Then we know what the connection can read
  And what it can change
  And how it signs in
  And whether Emgram's backend can call it at all

Scenario: Read first
  When it is first switched on
  Then only its read tools are enabled

Scenario: Writes arrive one type at a time
  When a write is enabled
  Then it starts at "Waits for you"
```

**Build notes.** **Nothing here is verified**: not what the booking system's connection exposes,
and not whether a Xano agent can call an outside connection of this kind. The spike is the first
task and may change stories 01–04. The founder supplies the access; the copilot never creates an
account or enters a password on anyone's behalf.

---

## 4. Governance

| Area | Rule |
|---|---|
| Tables | Connection catalogue; per-business switch (unique: business + connection); secret storage decided by the spike |
| Delete behaviour | Switching a connection off keeps its history. Removing a login is immediate and logged |
| Validation | A connection cannot be switched on without a working sign-in check |
| Error codes | `E-COP-050` connection not switched on · `E-COP-051` could not reach the system · `E-COP-052` sign-in refused · `E-COP-053` tool not classified. Feature `COP-6` |
| Events | Switched on/off; login set/replaced/removed (never the value); first failure and recovery |

## 5. Counter-measures

| Risk | Counter-measure |
|---|---|
| A secret leaks through a log or an error message | A test saves a known fake secret, exercises every path, then searches every log table and response for it |
| A connection used across businesses | COP-1's scope check covers connections; cross-business test |
| An outside system's text steers the copilot | Same rule and fixtures as COP-4 story 03 |
| A write goes out unapproved | Every write tool is an action type; unclassified tools wait (story 03) |
| Building this breaks COP-1 to COP-5 | It adds tools and action types to lists those epics already own; no rule is duplicated |

## 6. Test plan

| ID | Kind | What |
|---|---|---|
| SPIKE-COP-6 | Spike | The four questions in story 05, answered in writing before any build |
| FT-COP-6-01 | HTTP | On/off per business; cross-business refused |
| FT-COP-6-02 | HTTP | Fake-secret hunt across logs, maps, chat and responses |
| FT-COP-6-03 | HTTP | Read runs; write waits; unclassified waits |
| FT-COP-6-04 | HTTP | Failing connection: honest answer, one grouped Health entry |
| UI-COP-6-01 | Browser | Connections screen; Approval levels shows the new action types |
| REG | Suites | `npm test`, `tsc`, build; COP-1 and COP-2 matrices |

## 7. Test results

Not run. Nothing is built. The spike has not been done.
