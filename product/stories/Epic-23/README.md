# Epic-23 — START HERE. The copilot: an AI that thinks, plans, acts and learns, and asks first (COP-1 to COP-6)

> ## 📋 WRITTEN, NOT BUILT (2026-11-14, Fable 5.2). Nothing in Xano or the app was changed.
>
> Wait for the founder's "execute" before building. **Ask before every Xano push** (CLAUDE.md).
> A clickable mock-up of the approvals screen exists (fake data only) — see §3.

| File | What it is |
|---|---|
| `README.md` | This file. The idea, what exists, the gaps, the order, the models, the open decisions. |
| `EPIC-SEC-3-lock-the-ai-tool-door.md` | 🔴 The AI tool address answered with no sign-in (found 2026-11-14). **Do this before everything.** |
| `EPIC-COP-1-agent-identity-and-guardrails.md` | The copilot gets a name, the same locked doors as a person, a full log and an off switch. **Do this first.** |
| `EPIC-COP-2-approval-levels.md` | Three approval levels per action type, and one inbox for everything waiting. |
| `EPIC-COP-3-copilot-home-and-chat.md` | Its own "how I work" maps, one business at a time, and one chat you can reach from every screen. |
| `EPIC-COP-4-think-and-learn.md` | Goals and research become draft maps, with sources. Real results become suggested improvements. |
| `EPIC-COP-5-plan-and-act.md` | It turns approved maps into plans and does assigned work, through tools that do not exist yet. |
| `EPIC-COP-6-connections-library.md` | A library of connections to outside systems, per business. **Written for later** — not in the first build. |

---

## 1. Who you are working for

- Product manager, not an engineer, and the only support person. **ADHD, thinks visually.**
- **5 short bullets per reply, one line each.** Pain → fix → win lands best.
- A question is a question. A short reply is not a go. Ask before any Xano push.
- Examples (party rental, "$2M in 3 years", accounting research, a rental-booking system) are
  **illustrations**. Build the general pattern. Nothing in the code may assume an industry.

---

## 2. What the founder wants (2026-11-14, in their words)

> "I need a copilot that could not only help me do stuff but also think through things and build
> intelligence layers. It also needs its own personal library of intelligence layers."
>
> "Pin it on an architecture at a time. That way, it doesn't mix one architecture with another."
>
> "I don't want to approve every action — are there different approval levels?"

**Pain:** today's AI chat lives inside one map and only edits that map. It cannot hold a goal, plan
work, do work, or learn from what happened. And an AI that could do those things has no name, no
locked doors and no log.

**Fix:** one copilot per business that works on all three layers — Definition (maps), Commitment
(plans), Record (what was done) — always under one rule: **it drafts, the owner approves.**

**Win:** the owner states a goal; the copilot researches, proposes a strategy as maps, turns the
approved maps into plans, does the legwork, and gets better from real results.

### The four verbs, and where approval sits

| Verb | What the copilot does | What makes it real |
|---|---|---|
| **Think** | Turns a goal or research into draft maps in the business's architecture | The owner clicks **Publish version** (existing button) |
| **Plan** | Turns a published map into a draft plan | The owner clicks **Publish to live** (existing button) |
| **Act** | Does work and takes outside actions | Its **approval level** for that action type (COP-2) |
| **Learn** | Compares plan with actual, and reads the owner's edits; proposes changes | Proposals are drafts. It never changes a published version |

### Two kinds of map, never mixed

| Kind | Holds | Who shares it |
|---|---|---|
| **The copilot's own architecture** | "How I work": how to research, build maps, learn, ask for approval | Every business in the account (see decision D-2) |
| **A business's architecture** | What it knows and does for that business | That business only |

---

## 3. What already exists (verified 2026-11-14 — re-verify before building)

| Thing | State | Where |
|---|---|---|
| Access gates on Planner, Execution and Intelligent Layer requests | ✅ live (USR-2, commits `5b0844a`, `2f8bdeb`) | `apis/*/api_group.xs` |
| **AI and MCP tools go through those gates** | 🔴 **No.** "AI/MCP tools call functions directly and bypass every gate" | USR-2 commit note; map 226 gap 2 |
| An identity for an AI | 🟡 `agent_profile.kind = "ai"` exists (a name, no login, `user_id = 0`). Nothing acts *as* it | `static/tables/129_agent_profile.xs` |
| A log of tool calls | 🟡 `agent_tool_log` exists; map 226 says 17 of 37 tools write to it and **none records who** (not re-counted here) | `static/tables/11_agent_tool_log.xs` |
| A chat that belongs to a whole business, not one map | 🟡 `agent_conversation` already has `journey_architecture_id`. The chat screen is per map | `static/tables/4_agent_conversation.xs` |
| An AI row linked to its own operating-manual map | ✅ `journey_lens.agent_map_id` + `update_actor_identity` tool | `ai/tool/update_actor_identity.xs` |
| Web research | ✅ `web_search` tool (asks for the source URL to be cited) | `ai/tool/web_search.xs` |
| Map-building tools | ✅ 37 tools, with four known bugs (COP-1 story 06) | `ai/tool/` |
| Tools to create a plan, add a job, assign, schedule | ❌ none. The endpoints exist | map 226 gap 5 |
| Tools to see, start, finish, block or skip work; read plan vs actual | ❌ none. The endpoints exist | map 226 gap 6 |
| A label telling a research map from a runnable process | ❌ none | map 226 gap 7 |
| Connections to outside systems | ❌ none | — |
| The design for one business (illustration) | 📋 8 draft maps, architecture 46, maps 227–234; **owner 0, account 0** | `product/updates/2026-11-14_2150-UTC_ai-copilot-party-rentals-architecture.md` |
| Approvals screen mock-up | 🧪 fake data, no Xano, `http://localhost:5180` | `webapp/copilot-approvals-mock/index.html` |

---

## 4. Gaps this folder closes, and the ones it does not

| # | Gap | Epic |
|---|---|---|
| G-1 | An AI can act with no identity, past every gate, with no "who" in the log | COP-1 |
| G-2 | Nothing stops an AI from acting on the wrong business | COP-1 story 03 |
| G-3 | No way to say "do this yourself, ask me for that" | COP-2 |
| G-4 | No plan for an owner who does not answer while a customer waits | COP-2 story 06 |
| G-5 | A "sent" message cannot be undone; "Runs, then tells you" must say so honestly | COP-2 story 04 |
| G-6 | Web pages can contain text aimed at the AI ("ignore your rules…") | COP-4 story 03 |
| G-7 | Research can look like a tested process | COP-4 story 04 |
| G-8 | A goal like "$2M in 3 years" needs real numbers; the AI must not invent them | COP-4 story 01 |
| G-9 | Outside-system logins must never appear in a map, a log or a chat | COP-6 story 02 |

**Not in this folder:** moving a business's data from a spreadsheet into Xano (the illustration's
M3), and the rental-specific sub-journeys (maps 229–234). Those are business content, built *with*
the copilot once it exists — not platform features.

---

## 5. Build order and models

| # | Epic | Depends on | Model | Why that model |
|---|---|---|---|---|
| 0 | **SEC-3** Lock the AI tool door | USR-2 (live) | **Opus 5.5** | A guard on a public address. Found while starting COP-1 |
| 1 | **COP-1** Agent identity and guardrails | SEC-3 | **Opus 5.5** | Guards and tenancy. Every line is a permission. Story 06 (tool bug fixes) is Sonnet 5.5 |
| 2 | **COP-2** Approval levels | COP-1 | **Opus 5.5** for the gate (stories 01, 02, 06, 08); Sonnet 5.5 for the screens | A gate that leaks sends a customer a message nobody approved |
| 3 | **COP-3** Copilot home and chat | COP-1 | **Sonnet 5.5**; Opus review of the "one business only" rule | Mostly screens on storage that exists |
| 4 | **COP-4** Think and learn | COP-2, COP-3 | **Sonnet 5.5**; Opus review of story 03 (web text is data) | Prompt and tool work, well specified |
| 5 | **COP-5** Plan and act | COP-2, COP-3 | **Sonnet 5.5**; Opus review of anything near **Publish to live** | Thin wrappers over tested endpoints |
| 6 | **COP-6** Connections library | COP-2 | **Opus 5.5** for secrets (story 02); Sonnet 5.5 for the rest | Later. Stores other companies' logins |

- "Opus 5.5" means the strongest model available; **Fable 5.2 is also fine** for those stories.
- Run a review pass with that model **after each of COP-1, COP-2 and COP-6**.
- Fixtures, the junk-input list and repetitive tool wiring (logging on 37 tools) can go to Haiku 5.5.
- COP-3 can run in parallel with COP-2 (different files). COP-4 and COP-5 can run in parallel.

**House rules that apply to all six** (from CLAUDE.md — do not re-discover them):

- Additive only. No new column on a table with text validators. New facts go in a **side table
  with its own GET endpoint**.
- One rule, one function. The gate, the scope check and the level lookup each live in one place.
- An omitted optional input is `""` / `0` / `false`, never `null`. Pass an explicit flag.
- `db.patch` / `db.del` by a non-unique field touches **one** row. Query, then loop by `id`.
- Race protection is a **unique index**, not a transaction.
- No `redis.*` on this plan. Rate limits are a `db.query … count` against a log table.
- Before pushing a static path, check it is not shadowed by a dynamic one in the same group.
- After every push, a real smoke test with `runWorkspaceFunction` or real HTTP.
- Tests first. Then `npm test`, `tsc`, build and the existing suites, all green.
- Never fail silently: every refusal and every approval writes an event.

---

## 6. Decisions the founder still owns

Each has a default so the build is never blocked. Say the word to change one.

| # | Question | Default written into the stories |
|---|---|---|
| **D-1** | Where does the copilot's "brain" run? | **Inside Emgram** (a Xano agent, for the chat and for scheduled runs). The same tools stay reachable from an outside assistant, under the same identity and gates |
| **D-2** | Is the copilot's own "how I work" architecture shared across *all* customers, or one copy per account? | **One copy per account**, made from a starter template. A single shared copy would be a cross-account read — a much larger permission |
| **D-3** | Is an AI a real user row, or something separate? | **Its own kind of identity, shown on Manage users**, switched off the same way. Exact storage is COP-1's first design task (Opus) |
| **D-4** | Can the copilot ever click **Publish version** or **Publish to live** itself? | **No.** It proposes; a person clicks. Both stay locked at "Waits for you" |
| **D-5** | When the owner does not answer an approval, what happens? | **Remind, then expire. Never auto-approve.** The copilot may send a pre-approved "we'll get back to you" holding reply if that type is allowed |
| **D-6** | May the copilot do work assigned to it on a plan (as a performer)? | **Yes, but only work assigned to it by name**, and each action type still follows its level |
| **D-7** | A spending cap on AI use per business? | **Yes — a daily cap**, with a friendly "paused until tomorrow" and an event on Health |
| **D-8** | Starting levels for a brand-new business | Read and draft: **on its own**. Internal notes: **runs, then tells you**. Anything reaching a customer, a booking or money: **waits for you** |

---

## 7. How to report progress

- Edit each story's `**Status:**` line: `📋 Not started` → `🚧 In progress (model, date)` →
  `✅ Built (model, date)` or `🔴 Blocked — reason`.
- Every screen story is seen in a browser on real data before it is called done.
- Fill each epic's Test Results with real results. Not run = "not run".
- Stage files by name. Never commit `product/learning-fixes.md`, `.obsidian/`, the frontend zip,
  or loose screenshots.

---

## 8. Status

| Item | State |
|---|---|
| Epics + stories written | ✅ 2026-11-14 (Fable 5.2) |
| Founder review | ⏳ waiting |
| SEC-3 | 🟡 Door shut and proven 2026-11-14 (stories 01–03). Open: 04 tenancy inside tools (→ COP-1), 05 refusal logging, nightly probe |
| COP-1 | ✅ Built and reviewed (2026-11-15) |
| COP-2 | ✅ Built and proven (2026-11-15) — Undo and per-business reminder times deferred |
| COP-3 | ✅ Built (2026-11-15) — plan/work reading moves to COP-5; business-delete guard pending |
| COP-4 | ✅ Built (2026-11-15) — story 05 (learning) waits for COP-5 |
| COP-5 | 🟡 Partly built (2026-11-15) — story 04 (read plan vs actual) only; 01/03/05/06 need a founder decision |
| COP-7 | ✅ Stories 01–05 built and proven (2026-11-15, Fable 5.2); 06 (proof on real jobs) open — hardening from the Fable review |
| COP-6 | 📋 Not started — **deferred on purpose** ("you don't have to do it right now") |
| Approvals mock-up | 🧪 built, fake data, not committed |
