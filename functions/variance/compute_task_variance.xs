// VAR-1 (US-VAR-1-01, -02) — Per-task variance, derived, never stored.
// The backend twin of `webapp/protype-2/src/variance.ts::computeTaskVariance`;
// a golden fixture pins both sides to the same numbers.
//
// NULLABLE NUMBERS ARE `json`, NOT `int`. An optional `int` input here
// arrives as 0 when omitted, never null (CLAUDE.md), and 0 is a real,
// meaningful duration — there would be no way to tell "no expected
// duration" apart from "an expected duration of zero minutes". `json`
// can hold a genuine null, so that is what expected/scheduled/planned
// start are declared as.
//
// Events are processed IN THE ORDER GIVEN, never re-sorted — same
// convention as `log/replay_task` and the TypeScript twin: the caller
// queries with `sort = {occurred_at: "asc"}`. Re-sorting here would
// make W-VAR-002 (end earlier than start) impossible to ever detect.
//
// ⚠️ `==`/`!=` AGAINST `null` IS LOOSE: `0`, `""`, `false` and `[]`
// all test equal to `null` here (confirmed live — see CLAUDE.md). Every
// `== null`/`!= null` below is safe only because the value compared is
// always a real epoch-ms timestamp, never legitimately `0` in
// production. Proven live with golden cases using realistic timestamps
// (an offset-from-0 smoke test silently produced wrong output once,
// for exactly this reason — never use `0` as a stand-in timestamp).
//
// ON `reopened`, THE RESUMED ATTEMPT BEGINS AT THE REOPEN ITSELF, not
// null. `logModel.ts::canTransition` has no `in_progress`+`started`
// row, so a real log can never contain an explicit `started` right
// after a `reopened` — the reopen is the only signal that work
// resumed. Found live: a task reopened then completed directly (the
// UI doesn't even offer Start from `in_progress`) first came back
// `actual_minutes: null` with a spurious W-VAR-001, because the first
// version of this treated every reopen as "unknown start".
function "variance/compute_task_variance" {
  input {
    json events
    json expected_minutes
    json scheduled_minutes
    json planned_start_at
  }

  stack {
    var $first_start_at {
      value = null
    }

    var $current_attempt_start {
      value = null
    }

    var $last_span_start {
      value = null
    }

    var $last_completion_at {
      value = null
    }

    var $blocked_start {
      value = null
    }

    var $blocked_minutes {
      value = 0
    }

    foreach ($input.events) {
      each as $e {
        conditional {
          if ($e.event_type == "started") {
            conditional {
              if ($first_start_at == null) {
                var.update $first_start_at {
                  value = $e.occurred_at
                }
              }
            }

            conditional {
              if ($current_attempt_start == null) {
                var.update $current_attempt_start {
                  value = $e.occurred_at
                }
              }
            }
          }
        }

        conditional {
          if ($e.event_type == "blocked") {
            var.update $blocked_start {
              value = $e.occurred_at
            }
          }
        }

        conditional {
          if ($e.event_type == "unblocked" && $blocked_start != null) {
            var.update $blocked_minutes {
              value = $blocked_minutes + (($e.occurred_at - $blocked_start) / 60000)
            }

            var.update $blocked_start {
              value = null
            }
          }
        }

        conditional {
          if ($e.event_type == "completed" || $e.event_type == "skipped") {
            var.update $last_completion_at {
              value = $e.occurred_at
            }

            var.update $last_span_start {
              value = $current_attempt_start
            }
          }
        }

        conditional {
          if ($e.event_type == "reopened") {
            var.update $current_attempt_start {
              value = $e.occurred_at
            }

            var.update $last_span_start {
              value = null
            }

            var.update $last_completion_at {
              value = null
            }

            var.update $blocked_start {
              value = null
            }
          }
        }
      }
    }

    var $actual_minutes {
      value = null
    }

    conditional {
      if ($last_completion_at != null && $last_span_start != null) {
        var.update $actual_minutes {
          value = ($last_completion_at - $last_span_start) / 60000
        }
      }
    }

    var $start_lateness_minutes {
      value = null
    }

    conditional {
      if ($first_start_at != null && $input.planned_start_at != null) {
        var.update $start_lateness_minutes {
          value = ($first_start_at - $input.planned_start_at) / 60000
        }
      }
    }

    // Gap against expected.
    var $expected_gap_minutes {
      value = null
    }

    var $expected_gap_pct {
      value = null
    }

    conditional {
      if ($actual_minutes != null && $input.expected_minutes != null) {
        var.update $expected_gap_minutes {
          value = $actual_minutes - $input.expected_minutes
        }

        conditional {
          if ($input.expected_minutes != 0) {
            var.update $expected_gap_pct {
              value = (($expected_gap_minutes / $input.expected_minutes) * 100)|round:1
            }
          }
        }
      }
    }

    // Gap against scheduled.
    var $scheduled_gap_minutes {
      value = null
    }

    var $scheduled_gap_pct {
      value = null
    }

    conditional {
      if ($actual_minutes != null && $input.scheduled_minutes != null) {
        var.update $scheduled_gap_minutes {
          value = $actual_minutes - $input.scheduled_minutes
        }

        conditional {
          if ($input.scheduled_minutes != 0) {
            var.update $scheduled_gap_pct {
              value = (($scheduled_gap_minutes / $input.scheduled_minutes) * 100)|round:1
            }
          }
        }
      }
    }

    // Outlier: scheduled wins over expected as the reference.
    var $reference {
      value = $input.scheduled_minutes
    }

    conditional {
      if ($reference == null) {
        var.update $reference {
          value = $input.expected_minutes
        }
      }
    }

    var $is_outlier {
      value = false
    }

    conditional {
      if ($actual_minutes != null && $reference != null && $actual_minutes > (($reference * 2.0) > ($reference + 10) ? ($reference * 2.0) : ($reference + 10))) {
        var.update $is_outlier {
          value = true
        }
      }
    }

    // Data-quality warnings.
    var $warnings {
      value = []
    }

    conditional {
      if ($last_completion_at != null && $last_span_start == null) {
        array.push $warnings {
          value = "W-VAR-001"
        }
      }
    }

    conditional {
      if ($last_completion_at != null && $last_span_start != null && $last_completion_at < $last_span_start) {
        array.push $warnings {
          value = "W-VAR-002"
        }
      }
    }

    conditional {
      if ($actual_minutes != null && $actual_minutes > 1440) {
        array.push $warnings {
          value = "W-VAR-003"
        }
      }
    }

    conditional {
      if ($last_completion_at != null && $input.expected_minutes == null) {
        array.push $warnings {
          value = "W-VAR-004"
        }
      }
    }
  }

  response = {
    actual_minutes        : $actual_minutes
    blocked_minutes       : $blocked_minutes
    expected_gap_minutes  : $expected_gap_minutes
    expected_gap_pct      : $expected_gap_pct
    scheduled_gap_minutes : $scheduled_gap_minutes
    scheduled_gap_pct     : $scheduled_gap_pct
    start_lateness_minutes: $start_lateness_minutes
    is_outlier            : $is_outlier
    warnings              : $warnings
  }
}
