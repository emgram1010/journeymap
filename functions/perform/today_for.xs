// APP-1 — "What day is it, for this performer?"
//
// PHASE 0 OF THE TIMEZONE SEAM (learning-fixes.md, flag #4, raised
// 2026-10-15). There is no timezone anywhere in this system yet. This
// function exists so that gap has exactly ONE place to fix: today it
// returns the UTC calendar date; the founder has decided the eventual
// rule is the PERFORMER'S own timezone, then the account's, then UTC.
// When that data exists, only this function's body changes — nothing
// that calls it does.
//
// Deliberately takes `user_id` even though it is unused today: the
// call site is already correct for the day this starts mattering.
function "perform/today_for" {
  input {
    int user_id filters=min:1
  }

  stack {
    var $date {
      value = now|format_timestamp:"Y-m-d":"UTC"
    }
  }

  response = {date: $date}
}
