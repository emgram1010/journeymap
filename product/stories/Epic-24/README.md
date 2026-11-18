# Epic-24 — START HERE. Both AIs share one library of knowledge, check the real rules, and use the right model

> ## 📋 WRITTEN, NOT BUILT (2026-11-18, Opus 5.5). Nothing in Xano or the app was changed.
>
> Wait for the founder's go before building. **Ask before every Xano push** (CLAUDE.md).

| File | What it is |
|---|---|
| `README.md` | This file. The idea, the knowledge layers, the order, the models. |
| `EPIC-COP-10-publish-checklist-tool.md` | The map AI checks a map against the real publish checklist before you press **Publish version**. |
| `EPIC-COP-11-locks-and-tidy-library.md` | You can lock a skill so the AI can't change it; the library has a size limit and flags unused items. |
| `EPIC-COP-12-map-chat-reads-skills.md` | The map AI reads the same "How I work" skills (read-only, only the map-building ones). |
| `EPIC-COP-13-right-model-for-the-job.md` | Every agent moves to a current model; later, start cheap and ask before using a stronger one. |
| `EPIC-COP-14-emgram-operations.md` | Emgram maps its own way of working ("Who does the thinking": Max plan vs paid API), built through its own MCP door. |

---

## 1. Why (from the founder, 2026-11-18)

- There are **two AIs you talk to**: the main copilot (panel, scheduled runs) and the map chat
  (inside a journey map, the intelligence layer). Only the main copilot reads "How I work" today.
- The map AI can build every part of a publishable map, but it **cannot see the publish
  checklist**, so it cannot say "this will pass".
- "How I work" will grow. Nothing yet stops it from getting **bloated**, and nothing lets the owner
  say **"the AI may not touch this one"**.
- All 7 agents run on **Claude Sonnet 4.5**, which is older and dearer than Sonnet 5.5.

## 2. The four knowledge layers (the design both AIs follow)

| Layer | What it holds | Who can change it | Where it lives |
|---|---|---|---|
| **1. Rules** | Publish checklist, permissions, hard limits | Nobody through chat. Code only | Server functions (`pub/evaluate_gate`, `journey/tool_gate`, `copilot/skill_limits`) |
| **2. Skills** | "How I work": skills, exceptions, lessons, links | The main copilot (under its approval level) and the owner. Locked items: owner only | `copilot_skill` + versions (COP-9) |
| **3. Business memory** | Goals, notes, past jobs for one business | Main copilot and owner | `copilot_note`, goals, jobs (COP-4) |
| **4. Live data** | The map, plan and jobs as they are now | Through tools, never stored as knowledge | The normal tables |

**One rule, one place.** The AI never keeps its own copy of a rule. It calls the function that
the server itself uses, so the AI and the server can never disagree.

**One library, not two.** Both AIs read the same "How I work". Each item is tagged with the kind
of work it is for, and each AI loads only its kinds. The main copilot stays the only AI that writes.

## 3. Build order and models

| # | Epic | Depends on | Model | Why |
|---|---|---|---|---|
| 1 | **COP-10** Publish-checklist tool | PUB-1 (live) | **Sonnet 5.5** | A thin tool over an existing, tested function |
| 2 | **COP-11** Locks and a tidy library | COP-9 01–04 (live) | **Opus 5.5** for the lock (a guard); Sonnet 5.5 for the rest | A lock that leaks lets the AI overwrite the owner's words |
| 3 | **COP-12** Map chat reads skills | COP-11 (work kinds) | **Sonnet 5.5** | Read-only wiring of a loader that exists |
| 4 | **COP-13** Right model for the job | none for part A; COP-2 for part B | **Sonnet 5.5** part A; **Opus 5.5** part B (a new approval type and a spend cap) | Part B is a gate on money |

- COP-10 and COP-13 part A touch different files and can run in parallel.
- COP-11 should be built **together with COP-9 story 05** (trial before trust): both change how
  items are promoted, switched off and loaded.
- Fixtures and the test scenario list can go to Haiku 5.5.

**House rules** are the same as Epic-23 README §5 and CLAUDE.md. In particular: additive only, a
new field on a table with text validators goes in a side table with its own GET, `|contains:` does
not work on arrays, a `conditional` in a loop must branch on the loop item, and every push gets a
real smoke test.

### Build order (reviewed 2026-11-18)

| Step | Epic | Why here |
|---|---|---|
| 0 | ✅ **Real AI test** (done 2026-11-18: 8 of 8 on Sonnet 4.5, skill use recorded; commit e1ce703) | The baseline COP-13 needs, and the first real check of COP-9 skills |
| 1 | **COP-10** Publish-checklist tool | Small, read-only, and COP-14 needs it |
| 2 | **COP-13 part A** Move to Sonnet 5.5 | Saves money on every later test; can run in parallel with step 1 (different files) |
| 3 | **COP-14** Emgram operations | Eats our own dog food early; its gaps steer what comes next |
| 4 | **COP-11 + COP-9 story 05** Locks, tidy library, trial before trust | Build together; must exist before a second AI reads the library |
| 5 | **COP-12** Map chat reads skills | Needs COP-11's kinds of work |
| 6 | **COP-13 part B** Step up with approval | Last: needs real usage data to set the cap |

### Review notes (2026-11-18)

- **COP-11:** the duplicate-item rule sits only in Counter-measures; it needs its own story and test. The "suggest a change to a locked item" path forces the level to "wait", which changes `copilot/action_gate`; say so in Governance.
- **COP-12:** `record_skill_used` calls `journey/tool_gate` with map 0. Check that a map-chat ticket passes it before relying on it; otherwise pass the map id.
- **COP-13:** re-running a task on the strong copy "with the conversation so far" can hit Opus 5.5's preserved-thinking rules; re-run from the user messages and tool results, not the old thinking. E-COP-093 should be catalog owner `engineer`.
- **COP-13:** add the Max-plan rule: in-app AI is for when no one is present; the founder's own work goes through Claude on the Max plan (COP-14).
- **COP-10:** sound as written.

## 4. Decisions the founder owns

Each has a default so the build is never blocked.

| # | Question | Default written into the stories |
|---|---|---|
| **D-24-1** | Is anything the owner writes or edits locked automatically? | **Yes.** The owner can unlock it |
| **D-24-2** | How big may the library get? | **50 active items**, and **about 4,000 words** of skill text per run |
| **D-24-3** | When is an item "unused"? | **Not used in 30 days.** It is flagged, never retired automatically |
| **D-24-4** | Which kinds of work exist? | A fixed list: `map_building`, `planning`, `doing_work`, `research`, `general`. The owner can't add kinds in this epic |
| **D-24-5** | Which model does each agent start on? | **Sonnet 5.5** for all 7 |
| **D-24-6** | May the AI step up to a stronger model on its own? | **No by default.** A new approval type "use a stronger model", starting at "waits for you" |

| **D-24-7** | Where do outside-app connections go (e.g. Booqable)? | **Founder-only tool → separate connectors workspace; customer feature → Emgram COP-6** (COP-14-06) |
| **D-24-8** | Max plan or API? | **Someone at the keyboard → Claude on the Max plan via MCP; no one present or a customer's business → in-app copilot on the API** (COP-14) |

## 5. Status

| Item | State |
|---|---|
| Epics and stories written | ✅ 2026-11-18 (Opus 5.5) |
| Founder review | ⏳ waiting |
| COP-10 | 🟡 Built and live; Assistant agent needs the tool added in Xano (see its Results) |
| COP-11 | 📋 Not started |
| COP-12 | 🟡 Built as a read-only tool (not an endpoint change); kind filter waits on COP-11 |
| COP-13 | 📋 Not started |
| COP-14 | 📋 Not started |
