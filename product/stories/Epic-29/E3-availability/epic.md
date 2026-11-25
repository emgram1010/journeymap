# AVAIL-1 — Working days and time off

**Epic ID:** AVAIL-1 (E3 in this folder)
**Status:** 📋 Not built (docs only, 2026-11-25)
**Size:** M
**Model:** Sonnet 5.5.
**Depends on:** REQ-1 story 03 (a person on a plan knows their profile). Story 05 needs REPEAT-1 story 05 (the review mark).
**Read first:** `../README.md`.

---

## 1. Goal

**Pain:** the system will let a planner give Tuesday's work to someone who does not work
Tuesdays, or who is away that week. Nothing knows when anyone works.

**Win:** each person's working days and time off are recorded once. The system can answer, for
any person and any date: **are they working, and how many hours do they have left?**

Founder, 2026-11-25: availability applies to **every** piece of work, whatever it needs (D-4).

This epic **stores and answers**. Suggesting, warning and refusing are MATCH-1.

## 2. What exists today (repo and live compared 2026-11-25: planner code identical; see README F-6, F-8, F-15–F-17)

| Fact | Where |
|---|---|
| A profile has default daily hours (8); a person on a plan has daily hours (8) | tables 129, 116 |
| **No scheduling endpoint reads daily hours.** They are stored and shown, and nothing else | searched `apis/planner`, `functions/planner`, `functions/live` |
| No working days, no time off, anywhere | searched 2026-11-25 |
| A day is one person's row for one **plain date**, with a start time and no time zone | `static/tables/117_planner_timeline.xs` |
| A person can be inactive on a plan, off the roster, or have their login switched off | tables 116, 129, 133 |
| An AI member can be paused, by a person or automatically | `static/tables/172_ai_member_profile.xs`, table 174 |

## 3. Rule

**A person is available on a date when all of these are true:**

1. They are active (on the plan, on the roster, login not switched off; an AI is not paused).
2. It is one of their working days.
3. No time off covers that date.

**Hours left** on that date = their hours for that day − the minutes already scheduled on their
day. It is worked out when asked and never stored.

- A person with no working pattern recorded works **every day** at their daily hours. So nothing
  changes for anyone until a pattern is recorded.
- Dates are plain plan dates. No time zone is involved, the same as the planner's days today.
- Not available is a **refusal** (in MATCH-1). Not enough hours left is a **warning** (D-9).

## 4. Do not break

- With no pattern and no time off recorded, every person is available every day, as today.
- No column is added to `agent_profile`, `planner_agent` or `planner_timeline`.
- A published day is never changed by time off recorded afterwards.

## 5. Non-goals

- Part-day time off and shifts (D-13). Whole days only.
- Public holidays as a shared calendar (a pattern or time off per person covers the need for now).
- Requesting and approving leave. This records the answer, not the process.
- Syncing with an outside calendar.
- Changing a person's hours for one plan (that field already exists on the plan's person).

## 6. New tables (additive)

| Table | What it holds | Guard |
|---|---|---|
| `agent_profile_work_day` | Profile, weekday (1–7), hours for that weekday. A weekday with no row, on a profile that has any rows, is a day off | Unique (profile, weekday) |
| `agent_profile_time_off` | Profile, first day, last day, note, recorded by | Index on (profile, first day) |

## 7. Stories

| File | Story |
|---|---|
| `US-AVAIL-1-00-check-what-is-live.md` | Read-only: live vs repo, confirm nothing reads daily hours, how the board totals a day |
| `US-AVAIL-1-01-working-days.md` | Record which days a person works, and their hours |
| `US-AVAIL-1-02-time-off.md` | Record time off |
| `US-AVAIL-1-03-is-this-person-available.md` | One function that answers for any person and date |
| `US-AVAIL-1-04-the-board-shows-it.md` | The planner sees days off and hours left |
| `US-AVAIL-1-05-time-off-recorded-later.md` | Time off recorded after work was assigned marks that work for review |

## 8. Completion gate

- A person who works Monday to Thursday is not available on Friday.
- A person with no pattern is available every day.
- Time off from the 3rd to the 5th: not available on the 3rd, 4th and 5th; available on the 2nd and 6th.
- A paused AI member is not available.
- Hours left equals daily hours minus scheduled minutes, checked against a hand count.
- The board shows a day off and hours left.
- Time off recorded over assigned work marks each affected slot for review and never changes a published day.
- A second account sees nothing. Existing suites green. Test Results filled in.

## 9. Test Results

Not built. Nothing has been run.
