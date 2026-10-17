// TIME-1 (US-TIME-1-02) — The backend half of the canonical duration
// conversion. Same behaviour as webapp/protype-2/src/durationModel.ts,
// kept in sync by hand (same pattern as the error catalog — no shared
// build step between Xano and Vite). Used by PUB-1's version snapshot
// and JOB-1's hydrated task reads.
//
// value_text is TEXT, not decimal, because an omitted optional decimal
// input arrives as 0 (not null) in this XanoScript version — the same
// trap as VAL-1's max_length bug. Passing the raw text and parsing it
// here lets "not supplied" (empty string) be told apart from "supplied
// as zero" reliably, matching toMinutes(null, unit) vs toMinutes(0, unit).
function "duration_to_minutes" {
  description = "Converts a duration value+unit to whole minutes, rounded half-up. Never throws; returns null for anything not confidently convertible."

  input {
    text value_text? filters=trim {
      description = "The duration value as text, e.g. '1.5'. Empty/omitted = not set."
    }
    text unit? filters=trim {
      description = "minutes | hours | days | weeks"
    }
  }

  stack {
    var $workday_minutes {
      value = 480
    }

    var $minutes {
      value = null
    }

    var $has_value {
      value = ($input.value_text != null && $input.value_text != "")
    }

    var $has_unit {
      value = ($input.unit == "minutes" || $input.unit == "hours" || $input.unit == "days" || $input.unit == "weeks")
    }

    conditional {
      if ($has_value == true && $has_unit == true) {
        var $parsed {
          value = $input.value_text|to_decimal
        }

        var $round_trips {
          value = ($parsed|to_text) == $input.value_text
        }

        conditional {
          if ($round_trips == true && $parsed >= 0) {
            var $multiplier {
              value = 1
            }

            conditional {
              if ($input.unit == "hours") {
                var.update $multiplier {
                  value = 60
                }
              }

              elseif ($input.unit == "days") {
                var.update $multiplier {
                  value = $workday_minutes
                }
              }

              elseif ($input.unit == "weeks") {
                var.update $multiplier {
                  value = 5 * $workday_minutes
                }
              }
            }

            var $raw_minutes {
              value = $parsed * $multiplier
            }

            var.update $minutes {
              value = ($raw_minutes + 0.5)|floor
            }
          }
        }
      }
    }
  }

  response = {minutes: $minutes}
}
