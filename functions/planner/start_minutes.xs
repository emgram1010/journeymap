// SCHED-2 (US-SCHED-2-02) — The ONE start-time rule, "pin + flow".
//
// Walk the day in order: a task with an override sets the clock to that
// time; every task starts at the clock; the clock then advances by the
// task's minutes. With no overrides this is exactly PLN-7's original
// rule (day start + durations of everything before).
//
// Used by planner/derive_tasks (every planner screen) and
// variance/task_report. The browser twin is
// perform/performerView.ts::plannedStartsInOrder — both pinned by the
// same golden cases (UT-SCHED-2-G1..G5).
//
// `items` must already be in day order. Each item: {key, minutes,
// override} — `key` is caller-chosen and must be non-empty ("k:<id>"),
// `override` is "HH:MM" or "". Returns {starts: {key: minutes}}, minutes
// after midnight, unwrapped (callers wrap for display). A map, not a
// list, because position indexing into script-built arrays is
// unreliable in this engine.
//
// The branch condition reads the LOOP ITEM only — the one shape where a
// conditional inside a foreach keeps its writes.
function "planner/start_minutes" {
  input {
    text day_start
    json items
  }

  stack {
    var $cursor {
      value = ((($input.day_start|substr:0:2)|to_int) * 60) + (($input.day_start|substr:3:2)|to_int)
    }

    var $starts {
      value = {}
    }

    foreach ($input.items) {
      each as $i {
        conditional {
          if ($i.override != "") {
            var $ov_h {
              value = ($i.override|substr:0:2)|to_int
            }

            var $ov_m {
              value = ($i.override|substr:3:2)|to_int
            }

            var.update $cursor {
              value = ($ov_h * 60) + $ov_m
            }
          }
        }

        var.update $starts {
          value = $starts|set:$i.key:$cursor
        }

        var.update $cursor {
          value = $cursor + $i.minutes
        }
      }
    }
  }

  response = {starts: $starts}
}
