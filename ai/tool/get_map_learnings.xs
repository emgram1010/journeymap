// COP-4 story 05 - "where does reality differ from this map?" For ONE map: every finished step of its
// most recent jobs (up to 30), grouped by step (stage + lens), with how many times it was done, the
// average expected and actual minutes, and how often it ran over or under. The figures come from
// variance/task_report - the same function the report screen uses - and are only ADDED UP here,
// never recomputed. A step is flagged (`longer` / `shorter`) only when there are enough samples
// (min_samples, never below 3: one or two examples are not a pattern), most of them point the same
// way, and the average gap is at least 20%. Read-only: it proposes nothing by itself and changes
// nothing; the copilot turns a flagged row into a DRAFT edit and a "why" with these figures.
// The gate checks the caller, the map and the business pin (journey/tool_gate, kind read).
// No `if` inside the loops: a sample is counted by multiplying with a 0/1 flag (CLAUDE.md).
tool get_map_learnings {
  instructions = "For one map (journey_map_id): how long each step really took across its finished jobs, against what the map expects. Each row has samples, avg_expected_minutes, avg_actual_minutes, gap_minutes, gap_pct, times_over, times_under, enough (enough samples to mean anything), longer and shorter (a real pattern). Only propose a change for a row where longer or shorter is true, and quote samples, avg_expected_minutes and avg_actual_minutes exactly as returned. Never propose anything from a row where enough is false - say there is not enough data yet. Never compute figures yourself."

  input {
    int journey_map_id filters=min:1

    int min_samples? {
      description = "How many finished examples a step needs before it counts as a pattern. Leave empty for 3. Values below 3 are treated as 3."
    }

    text ticket? filters=trim {
      description = "COP-1 run ticket from your context. If you were given one, pass it on every tool call exactly as given. Otherwise leave it empty."
    }
  }

  stack {
    function.run "journey/tool_gate" {
      input = {journey_map_id: $input.journey_map_id, ticket: $input.ticket, tool: "get_map_learnings", kind: "read"}
    } as $cop1_gate

    var $caller_account {
      value = $cop1_gate.account_id ?? 0
    }

    db.query journey_map {
      where = $db.journey_map.id == $input.journey_map_id
      return = {type: "single"}
      output = ["id", "account_id", "title"]
    } as $map

    var $map_title {
      value = ($map|get:"title":"") ?? ""
    }

    var $map_account {
      value = ($map|get:"account_id":0) ?? 0
    }

    precondition ($caller_account != 0 && $map_account == $caller_account) {
      error_type = "notfound"
      error = "Map not found"
    }

    var $min {
      value = 3
    }

    conditional {
      if ($input.min_samples > 3) {
        var.update $min {
          value = $input.min_samples
        }
      }
    }

    conditional {
      if ($min > 50) {
        var.update $min {
          value = 50
        }
      }
    }

    db.query journey_map_version {
      where = $db.journey_map_version.journey_map_id == $input.journey_map_id
      return = {type: "list"}
      output = ["id"]
    } as $versions

    var $version_ids {
      value = [-1]
    }

    foreach ($versions) {
      each as $v {
        array.push $version_ids {
          value = $v.id
        }
      }
    }

    db.query work_item {
      where = $db.work_item.journey_map_version_id in $version_ids && $db.work_item.account_id == $caller_account
      sort = {work_item.id: "desc"}
      return = {type: "list"}
      output = ["id"]
    } as $all_jobs

    var $jobs {
      value = $all_jobs|slice:0:30
    }

    var $job_total {
      value = $all_jobs|count
    }

    var $jobs_read {
      value = $jobs|count
    }

    // Per step ("k:" ~ stage ~ "::" ~ lens): samples and sums. Keys are prefixed so none is ever empty.
    var $cnt {
      value = {}
    }

    var $sum_e {
      value = {}
    }

    var $sum_a {
      value = {}
    }

    var $over {
      value = {}
    }

    var $under {
      value = {}
    }

    var $stage_of {
      value = {}
    }

    var $lens_of {
      value = {}
    }

    var $k {
      value = ""
    }

    var $e {
      value = 0
    }

    var $a {
      value = 0
    }

    var $use {
      value = 0
    }

    var $prev {
      value = 0
    }

    var $next {
      value = 0
    }

    var $flag {
      value = 0
    }

    foreach ($jobs) {
      each as $j {
        function.run "variance/task_report" {
          input = {work_item_id: $j.id}
        } as $rep

        foreach ($rep.tasks) {
          each as $t {
            var.update $k {
              value = "k:" ~ $t.stage_key ~ "::" ~ $t.lens_key
            }

            var.update $e {
              value = $t.expected_minutes ?? 0
            }

            var.update $a {
              value = $t.actual_minutes ?? 0
            }

            // A sample counts when the step is done and both figures are real (above zero).
            var.update $use {
              value = (($t.status == "done") && ($e > 0) && ($a > 0))|to_int
            }

            var.update $stage_of {
              value = $stage_of|set:$k:$t.stage_key
            }

            var.update $lens_of {
              value = $lens_of|set:$k:$t.lens_key
            }

            var.update $prev {
              value = (($cnt|get:$k:null) ?? 0)
            }

            var.update $next {
              value = $prev + $use
            }

            var.update $cnt {
              value = $cnt|set:$k:$next
            }

            var.update $prev {
              value = (($sum_e|get:$k:null) ?? 0)
            }

            var.update $next {
              value = $prev + ($use * $e)
            }

            var.update $sum_e {
              value = $sum_e|set:$k:$next
            }

            var.update $prev {
              value = (($sum_a|get:$k:null) ?? 0)
            }

            var.update $next {
              value = $prev + ($use * $a)
            }

            var.update $sum_a {
              value = $sum_a|set:$k:$next
            }

            var.update $prev {
              value = (($over|get:$k:null) ?? 0)
            }

            var.update $flag {
              value = ($a > $e)|to_int
            }

            var.update $next {
              value = $prev + ($use * $flag)
            }

            var.update $over {
              value = $over|set:$k:$next
            }

            var.update $prev {
              value = (($under|get:$k:null) ?? 0)
            }

            var.update $flag {
              value = ($a < $e)|to_int
            }

            var.update $next {
              value = $prev + ($use * $flag)
            }

            var.update $under {
              value = $under|set:$k:$next
            }
          }
        }
      }
    }

    var $rows {
      value = []
    }

    var $flagged {
      value = 0
    }

    var $keys {
      value = $cnt|keys
    }

    var $n {
      value = 0
    }

    var $den {
      value = 1
    }

    var $se {
      value = 0
    }

    var $sa {
      value = 0
    }

    var $se_den {
      value = 1
    }

    var $avg_e {
      value = 0
    }

    var $avg_a {
      value = 0
    }

    var $gap_pct {
      value = 0
    }

    var $n_over {
      value = 0
    }

    var $n_under {
      value = 0
    }

    var $enough {
      value = false
    }

    var $longer {
      value = false
    }

    var $shorter {
      value = false
    }

    foreach ($keys) {
      each as $key {
        var.update $n {
          value = (($cnt|get:$key:null) ?? 0)
        }

        // Never divide by zero: a step with no usable sample divides by 1 and shows zeros.
        var.update $den {
          value = $n + (($n == 0)|to_int)
        }

        var.update $se {
          value = (($sum_e|get:$key:null) ?? 0)
        }

        var.update $sa {
          value = (($sum_a|get:$key:null) ?? 0)
        }

        var.update $se_den {
          value = $se + (($se == 0)|to_int)
        }

        var.update $avg_e {
          value = ($se / $den)|to_int
        }

        var.update $avg_a {
          value = ($sa / $den)|to_int
        }

        var.update $gap_pct {
          value = ((($sa - $se) * 100) / $se_den)|to_int
        }

        var.update $n_over {
          value = (($over|get:$key:null) ?? 0)
        }

        var.update $n_under {
          value = (($under|get:$key:null) ?? 0)
        }

        var.update $enough {
          value = ($n >= $min)
        }

        var.update $longer {
          value = ($n >= $min) && (($n_over * 2) > $n) && ($gap_pct >= 20)
        }

        var.update $shorter {
          value = ($n >= $min) && (($n_under * 2) > $n) && ($gap_pct <= -20)
        }

        var.update $flagged {
          value = $flagged + ($longer|to_int) + ($shorter|to_int)
        }

        array.push $rows {
          value = {
            stage_key           : (($stage_of|get:$key:null) ?? "")
            lens_key            : (($lens_of|get:$key:null) ?? "")
            samples             : $n
            avg_expected_minutes: $avg_e
            avg_actual_minutes  : $avg_a
            gap_minutes         : ($avg_a - $avg_e)
            gap_pct             : $gap_pct
            times_over          : $n_over
            times_under         : $n_under
            enough              : $enough
            longer              : $longer
            shorter             : $shorter
          }
        }
      }
    }
  }

  response = {journey_map_id: $input.journey_map_id, map_title: $map_title, jobs_found: $job_total, jobs_read: $jobs_read, min_samples: $min, flagged: $flagged, steps: $rows}
}
