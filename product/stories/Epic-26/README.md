# Epic-26 — START HERE. Soft delete (archive) and hard delete

> ## 🔴 SENSITIVE WORK. THIS FOLDER BUILDS DELETE FEATURES.
>
> - **DEL-2 is a SOFT delete (archive).** It hides things. Nothing is removed. It can be undone.
> - **DEL-3 is a HARD delete.** It removes rows from the database **permanently. It cannot be undone.**
>
> A mistake while building either one can hide or destroy the founder's real data.
> **Written, not built (2026-11-20). Nothing in Xano or the app was changed.**

| File | What it is |
|---|---|
| `README.md` | This file. The warning, the rules, the order. |
| `EPIC-DEL-2-archive-soft-delete.md` | 🟡 SOFT. Archive and Restore for maps, businesses and plans; the AI agent may archive without asking. **Build first.** |
| `EPIC-DEL-3-hard-delete-test-data.md` | 🔴 HARD. Permanently remove items marked as test data. Person-only. **Build second, only after a separate go.** |

---

## 1. To the AI agent building this: say this to the founder BEFORE any work

Do not start quietly. Your **first message** in a session that builds anything in this folder
must tell the founder, in plain words, all of the following. Use short bullets (CLAUDE.md).

1. **Which delete you are about to build:** "This is the SOFT delete (archive): undoable, nothing is removed" or "This is the HARD delete: permanent, it cannot be undone".
2. **That the work is sensitive and potentially destructive**, and that you will ask before every Xano push.
3. **Which story** you are starting, and which model fits it (see each epic's Model guidance).
4. **What you will NOT touch:** real data in account 2, map 178 and its business, the history tables.
5. Then **wait for the founder's go.** A short reply to a question is not a go (memory: confirm before executing).

Repeat the soft/hard label every time you report back, for example: "🟡 SOFT, story 03 done" or
"🔴 HARD, story 02 dry run only, nothing deleted". Never write just "delete" without saying which.

**If you are unsure whether an action is soft or hard, treat it as hard: stop and ask.**

## 2. Hard rules for building in this folder

These are on top of CLAUDE.md, not instead of it.

| # | Rule |
|---|---|
| 1 | **Ask before every Xano push**, every schema change and every run that writes. One yes covers one push. |
| 2 | **Test only on test account 13**, on fixtures you create for the test and name "(safe to delete)". Never on account 2. Never on map 178 or anything in its business. |
| 3 | **Never run a hard delete on real data to "see if it works".** Prove rollback on a scratch copy. |
| 4 | **Dry run first, always.** Any function that archives or deletes many rows takes `dry_run` and is run that way first; show the founder the counts before the real run. |
| 5 | **Do not loosen the history guard** (`webapp/protype-2/src/ops/historyTables.ts`). The one possible exception is DEL-3 decision D-3, and it needs the founder's explicit yes. |
| 6 | **Many rows = query, then loop by id, inside `db.transaction`.** `db.patch` and `db.del` by field touch only the first match and report success. |
| 7 | **After every push, a live smoke test**, then re-query the rows yourself. Do not trust a function's own "deleted: 12". |
| 8 | **The AI agent gets an archive tool and a restore tool. It never gets a hard-delete tool**, in the app or on the outside MCP door. |
| 9 | **Verify live before you build.** Local files may be behind live (DEL-2 story 01 exists for this). If they differ, stop and ask. |
| 10 | **Finish DEL-2 and get its completion gate signed off before any DEL-3 work.** DEL-3 depends on archive, and soft delete may turn out to be enough. |

## 3. Why (from the founder, 2026-11-20)

- A test map ("Moon bouncer repair", 7 jobs) could not be removed. It could not even be hidden.
- Reason: Emgram never deletes work history, and today even the soft delete is refused when a map has jobs.
- There is no "delete plan" at all, only archive, and archiving a plan does not free its maps.
- The founder's call: archive should be the normal delete; hard delete should be rare and very guarded.

## 4. What the two epics do

| | 🟡 DEL-2 Archive (soft) | 🔴 DEL-3 Hard delete |
|---|---|---|
| What happens | Hidden, frozen, no new work | Rows removed for good |
| Undo | Restore, any time | None |
| Who | Owner or admin; **the AI agent too** | Owner or admin, **a person only** |
| Does the AI ask first? | No. It runs, then tells you with Undo. It stops and asks only when work is in progress | The AI can never do it |
| What it can be used on | Maps, businesses, plans | Only items marked as test data, already archived |
| Safety steps | See what it touches, confirm | Mark as test, archive, read the dry run, type the name |
| Running work | Finishes normally | Must not exist outside the test item |
| What the AI can read | **Nothing from an archived item**, until it is restored | Nothing: it is gone |

## 5. The order

| # | Story | Kind | Model |
|---|---|---|---|
| 1 | DEL-2-01 Inventory of what is live (read-only) | 🟡 | Sonnet 5.5 |
| 2 | DEL-2-02 One impact check | 🟡 | Sonnet 5.5 |
| 3 | DEL-2-03 A person can always archive | 🟡 | Opus 5.5 |
| 4 | DEL-2-04 Archived items accept no new work | 🟡 | Opus 5.5 |
| 5 | DEL-2-05 Restore | 🟡 | Sonnet 5.5 |
| 6 | DEL-2-06 "Delete" on a plan means archive | 🟡 | Sonnet 5.5 |
| 7 | DEL-2-07 The AI agent archives without asking | 🟡 | Opus 5.5, then a review pass |
| 8 | DEL-2-08 Health shows archives | 🟡 | Sonnet 5.5 |
| 9 | DEL-2-09 AI agents do not read archived things (server-enforced) | 🟡 | Opus 5.5, then a review pass |
| — | **Gate: founder signs off DEL-2. Decide whether DEL-3 is still needed.** | | |
| 10 | DEL-3 decision D-3 (may test data's history be removed?) | 🔴 | founder |
| 11 | DEL-3-01 Mark as test data | 🔴 | Opus 5.5 |
| 12 | DEL-3-02 Dry run | 🔴 | Opus 5.5 |
| 13 | DEL-3-03 The hard delete | 🔴 | Opus 5.5, independent review before the push |
| 14 | DEL-3-04 Receipt and copy | 🔴 | Opus 5.5 |

## 6. Decisions

| Decision | Status |
|---|---|
| Archive is the normal delete; hard delete is rare | ✅ founder, 2026-11-20 |
| The AI agent archives without asking, then tells the owner | ✅ founder, 2026-11-20 |
| With work in progress, the agent stops and asks; a person sees a warning | ✅ founder, 2026-11-20 |
| Work in progress finishes normally after an archive | ✅ founder, 2026-11-20 |
| No AI agent reads or uses an archived item's knowledge; the server enforces it | ✅ founder, 2026-11-20 |
| Privacy erasure and account closure are a later epic | ✅ founder, 2026-11-20 |
| May a hard delete of test data also remove its frozen versions, jobs and activity log? (DEL-3 D-3) | ❓ **open** |

## 7. Related work

- `Epic-6/EPIC-DEL-1-map-and-architecture-delete-safety.md`: the guards these epics build on, and the record of a real map lost to a delete.
- `Epic-23/EPIC-COP-2-approval-levels.md`: the approval levels the agent's archive uses.
- `Epic-24/EPIC-COP-11-locks-and-tidy-library.md`: "force wait" and "an approval is for one version", both reused here.
