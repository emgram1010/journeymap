// REQ-1 story 02 — is a requirement held ON THE DATE OF THE WORK? Pure: no database, and NO CLOCK. `held_until` is "YYYY-MM-DD" or empty; `on_date` is a plain plan date. An empty `held_until` in any form (missing, "", spaces) means NO END: 0, "" and null all compare equal in this engine, so the rule is written as "it ends only when a real date is present". The last day counts: held until 2027-03-31 is held on 2027-03-31 and not on 2027-04-01. "Ends soon" is within 30 days, counted from the date of the work, and only while it is still held. A string that is not a real calendar day (2027-13-45) is reported as `bad_date`, so a caller can refuse it on the way in, and counts as no end. The TypeScript twin is requirementModel.ts (holdingState); both are pinned to the same examples. Dates are compared as timestamps made from the text, never as text.
function "req/holding_state" {
  input {
    text held_until? filters=trim
    text on_date filters=trim
  }

  stack {
    var $has_shape {
      value = "/^[0-9]{4}-[0-9]{2}-[0-9]{2}$/"|regex_matches:$input.held_until
    }

    var $until_ms {
      value = 0
    }

    var $parsed {
      value = false
    }

    // to_timestamp THROWS on a day that does not exist (2027-13-45), so the parse is guarded: such a value is "bad_date", never an error.
    conditional {
      if ($has_shape == true) {
        try_catch {
          try {
            group {
              stack {
                var.update $until_ms {
                  value = $input.held_until|to_timestamp
                }

                var.update $parsed {
                  value = true
                }
              }
            }
          }

          catch {
            var.update $parsed {
              value = false
            }
          }
        }
      }
    }

    var $round_trip {
      value = (($parsed == true) ? ($until_ms|format_timestamp:"Y-m-d":"UTC") : "")
    }

    var $real_date {
      value = ($parsed == true) && ($round_trip == $input.held_until)
    }

    var $bad_date {
      value = ($input.held_until != "") && ($real_date == false)
    }

    var $on_ms {
      value = $input.on_date|to_timestamp
    }

    var $days_left {
      value = (($until_ms - $on_ms) / 86400000)|round
    }

    var $held {
      value = ($real_date == false) || ($days_left >= 0)
    }

    var $ends_soon {
      value = ($real_date == true) && ($days_left >= 0) && ($days_left <= 30)
    }
  }

  response = {
    held     : $held
    ends_soon: $ends_soon
    has_end  : $real_date
    bad_date : $bad_date
    days_left: (($real_date == true) ? $days_left : null)
    until    : (($real_date == true) ? $input.held_until : "")
  }
}
