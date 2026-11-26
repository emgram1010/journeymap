// REPEAT-1 stories 01 + 06 — THE one rule for a repeat period's dates: where it starts, where it ends, how far everything moves, and whether it may be made. Pure: no database. repeat/build_plan (one period, the preview and the copy) and repeat/list_periods (several periods) both call it, so the preview and a multi-period repeat can never disagree about a date. A period is as long as the source plan; with no start date given it starts the day after the source ends. A bad start date (E-REPEAT-002: wrong shape, or not a real day such as 2027-13-45) or a window that overlaps the source (E-REPEAT-003) is returned as reject_code / reject_msg, not thrown, so the caller can log the refusal before raising it. Dates are YYYY-MM-DD text. All arithmetic is done from the dates passed in, never from a previous result.
function "repeat/period_dates" {
  input {
    text src_start filters=trim
    text src_end filters=trim
    text start_date? filters=trim
  }

  stack {
    var $src_start_ms {
      value = $input.src_start|to_timestamp
    }

    var $src_end_ms {
      value = $input.src_end|to_timestamp
    }

    var $length_days {
      value = (($src_end_ms - $src_start_ms) / 86400000) + 1
    }

    var $new_start_ms {
      value = $src_end_ms + 86400000
    }

    var $has_start {
      value = ($input.start_date != null && $input.start_date != "")
    }

    var $shape_ok {
      value = "/^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])$/"|regex_matches:$input.start_date
    }

    var $reject_code {
      value = ""
    }

    var $reject_msg {
      value = ""
    }

    // to_timestamp throws on a day that does not exist; the catch leaves the default in place and the round trip below refuses it.
    try_catch {
      try {
        group {
          stack {
            conditional {
              if ($has_start == true && $shape_ok == true) {
                var.update $new_start_ms {
                  value = $input.start_date|to_timestamp
                }
              }
            }
          }
        }
      }

      catch {
        var.update $shape_ok {
          value = false
        }
      }
    }

    var $new_start {
      value = $new_start_ms|format_timestamp:"Y-m-d":"UTC"
    }

    // A date that has the right shape but is not a real day (2026-13-45) does not survive the round trip.
    conditional {
      if ($has_start == true && ($shape_ok == false || $new_start != $input.start_date)) {
        var.update $reject_code {
          value = "E-REPEAT-002"
        }

        var.update $reject_msg {
          value = "Pick a start date for the new plan. (E-REPEAT-002)"
        }
      }
    }

    var $new_end_ms {
      value = $new_start_ms + (($length_days - 1) * 86400000)
    }

    var $new_end {
      value = $new_end_ms|format_timestamp:"Y-m-d":"UTC"
    }

    var $shift_days {
      value = ($new_start_ms - $src_start_ms) / 86400000
    }

    var $weekdays_align {
      value = (($shift_days % 7) == 0)
    }

    var $overlaps {
      value = ($new_start_ms <= $src_end_ms && $new_end_ms >= $src_start_ms)
    }

    conditional {
      if ($reject_code == "" && $overlaps == true) {
        var.update $reject_code {
          value = "E-REPEAT-003"
        }

        var.update $reject_msg {
          value = "The new plan would overlap this one. Pick a start date after this plan ends. (E-REPEAT-003)"
        }
      }
    }
  }

  response = {
    reject_code   : $reject_code
    reject_msg    : $reject_msg
    new_start     : $new_start
    new_end       : $new_end
    shift_days    : $shift_days
    weekdays_align: $weekdays_align
    length_days   : $length_days
  }
}
