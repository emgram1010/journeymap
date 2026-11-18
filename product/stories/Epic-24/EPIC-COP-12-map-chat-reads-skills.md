# EPIC-COP-12 — The map AI reads "How I work" too (read-only, map-building skills only)

**Status:** 📋 Not started
**Model:** **Sonnet 5.5**. It wires an existing loader into an existing endpoint.
**Depends on:** COP-9 stories 01–04 (live), **COP-11 story 02** (kinds of work, so the map AI loads only its own).
**Risk:** low–medium. The map AI gains no write power; the risk is cost and a wrong skill reaching it.

---

## 1. Goal

**Pain:** there are two AIs you talk to. A lesson you teach the main copilot ("every stage needs
a 'done when' written as something you can check") never reaches the map chat, because the map
chat's agents (Journey Map Builder, Journey Map Assistant, Journey Map Chat Agent, all called from
endpoint 52) never load "How I work". So the same lesson has to be taught twice, or the two AIs
build maps differently.

**Fix:** endpoint 52 loads "How I work" through the **same** loader the copilot uses
(`copilot/skill_library`), filtered to `map_building` and `general`, and adds it to the map AI's
context as a "How I work" section. The map AI **reads only**. The main copilot stays the only AI
that writes skills.

**Win:** teach once, and both AIs build maps the same way.

### Who does what

```
 Main copilot                         Map AI (endpoint 52)
  reads all kinds                      reads map_building + general only
  writes skills (COP-9, under level)   never writes skills
  records which skill it used          records which skill it used (bookkeeping only)
                \                     /
                 "How I work" (one library, copilot_skill)
```

---

## 2. Stories

### US-COP-12-01 — The map AI loads the map-building skills

**As an** owner **I want** the map AI to follow the same map-building skills as the copilot
**so that** I teach a lesson once.

```gherkin
Scenario: builder, assistant and chat modes
  When I send a message in a journey map's AI chat, in any mode
  Then endpoint 52 calls copilot/skill_library with kinds map_building and general,
  the map's account and the map's business
  And the agent's context has a "How I work (your skills)" section with what it returned

Scenario: same rules as the copilot
  Then retired items, items switched off for this business, and items scoped to another business are not loaded
  # these rules already live in skill_library; the endpoint adds none of its own

Scenario: other kinds stay out
  Given a planning skill and a map_building skill
  Then the map AI sees the map_building one and not the planning one

Scenario: nothing to load
  Given "How I work" has no map_building or general items
  Then the section is left out and the chat works exactly as today
```

### US-COP-12-02 — Never fails the chat

**As an** owner **I want** the map chat to keep working if the library can't be read **so that**
a skills problem never blocks my work.

```gherkin
Scenario: the loader fails
  Given skill_library fails
  Then the chat carries on without the section
  And E-COP-080 is recorded (the loader already does this), so Health shows it

Scenario: a map with no account
  Given an old map with account_id 0
  Then nothing is loaded and nothing is logged as a failure
  # the loader refuses account 0 by design; this is not an error
```

### US-COP-12-03 — The map AI can't write skills

**As an** owner **I want** only the main copilot to change "How I work" **so that** there is one
writer and one place to undo.

```gherkin
Scenario: no write tools
  Then none of the three map agents list save_skill or retire_skill

Scenario: it may record use
  Then the map agents list record_skill_used, so map-chat runs count toward a skill's trial and "last used"
  And the recorded use carries the map chat's conversation id and no copilot run id

Scenario: a correction in the map chat
  When I correct the map AI ("stages need a checkable 'done when'")
  Then it follows the correction in this chat
  And tells me in one line that the copilot can save it as a skill if I ask it there
  # saving from the map chat is out of scope (see §6)
```

### US-COP-12-04 — Cost stays visible

**As an** owner **I want** to see what the extra context costs **so that** I can switch it off if
it isn't worth it.

```gherkin
Scenario: a switch
  Then a feature flag "map chat reads skills" is on by default and can be turned off per account
  # account_feature_flag (GOV-1), no new table

Scenario: size recorded
  Then each map-chat turn records how many items and words of skills it loaded, next to the existing turn log
```

---

## 3. Governance

- **Tables:** none new. The flag is a row in `account_feature_flag`. Skill use goes in the existing `copilot_skill_use`.
- **Changed live items (fetch live source first, git HEAD is the rollback):** endpoint 52; agents Journey Map Builder, Journey Map Assistant, Journey Map Chat Agent (prompt section and the `record_skill_used` tool).
- **Validation:** none new; the loader validates.
- **Error codes:** reuse E-COP-080. No new code.
- **Events:** `copilot.skill_library.loaded` with `source: "map_chat"` on success (only when something loaded); failure is the loader's E-COP-080.
- **Delete behaviour:** none.

## 4. Counter-measures

| Risk | Counter-measure |
|---|---|
| A second writer appears | Map agents get no save or retire tool; FT-COP-12-03 checks the live tool lists |
| Planning skills confuse the map AI | Load by kind (COP-11-02), map_building and general only |
| Every map chat gets dearer | Load cap (COP-11-03), a per-account flag, words loaded recorded per turn |
| Endpoint 52 is very large (3,300+ lines) and fragile | One small addition near the context build; push one item at a time; smoke test each mode |
| `record_skill_used` from the map chat needs a run ticket | Endpoint 52 already mints a COP-1 ticket (`usr/mint_tool_ticket`); reuse it |

## 5. Test plan

| ID | Type | Checks |
|---|---|---|
| FT-COP-12-01 | Function | Endpoint 52 in builder, assistant and chat modes: section present, only map_building + general |
| FT-COP-12-02 | Function | Switched-off and other-business items absent; loader failure → chat still answers, E-COP-080 logged |
| FT-COP-12-03 | Function | Live tool lists: no save_skill/retire_skill on the three map agents; record_skill_used present |
| FT-COP-12-04 | Function | Flag off → no section; words loaded recorded per turn |
| AI-COP-12-01 | Real AI chat | A map_building skill ("every stage needs a checkable 'done when'") is followed by the map AI in a fresh map |
| UT-COP-12-* | Unit | Flag listed in the feature-flag manifest |

## 6. Out of scope (later)

- Saving a lesson **from** the map chat. If wanted, it should hand the lesson to the main copilot as an approval item, not write directly. Write it as its own story when asked.
- The older helper agents (`journey_map_orchestrator`, `journey_compare_analyst`): check whether they are still used before wiring them.

## 7. Test results

Not run.
