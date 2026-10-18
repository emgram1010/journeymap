// APP-1 — "What day is it, for this performer?"
//
// PHASE 1 OF THE TIMEZONE SEAM (learning-fixes.md, flag #4, raised
// 2026-10-15; built as GAP-FIX W8 on 2026-10-17). This function has
// always existed so the gap had exactly ONE place to fix, and this is
// that fix — nothing that calls it changed shape.
//
// THE RULE: the performer's own zone, then the account's, then UTC.
// This builds the first and the last. The zone arrives as an IANA name
// on the request (`tz`), and the DATE IS STILL COMPUTED FROM THE
// SERVER'S CLOCK — only the zone it is read in comes from the caller.
// That distinction is the whole point: APP-1 deliberately refuses to
// trust a device's clock for "what day is it", because a wrong clock
// would silently show the wrong day's work. A wrong zone name cannot
// do that; at worst it shifts the boundary by hours, and a junk name
// falls back to UTC on its own (confirmed live: "Not/AZone" and ""
// both return the UTC date, no error).
//
// The account default is still missing because there is nowhere to
// store it — a timezone column on `user` or `account` is a schema
// change, and those need the founder's approval (CLAUDE.md). When it
// exists, it slots in as the middle fallback here and nowhere else.
//
// `user_id` stays required and stays unused for the same reason it
// always was: the call site is already correct for the day a stored
// per-user preference lands.
function "perform/today_for" {
  input {
    int user_id filters=min:1
    text tz? filters=trim
  }

  stack {
    var $zone {
      value = "UTC"
    }

    // `!= ""` also excludes null here: this engine compares loosely, so
    // "" == null is true (CLAUDE.md). The length cap is a sanity bound,
    // not validation — an unrecognised zone is handled by the filter
    // itself, which falls back to UTC rather than throwing.
    conditional {
      if ($input.tz != "" && ($input.tz|strlen) <= 64) {
        var.update $zone {
          value = $input.tz
        }
      }
    }

    var $date {
      value = now|format_timestamp:"Y-m-d":$zone
    }
  }

  response = {date: $date, zone: $zone}
}
