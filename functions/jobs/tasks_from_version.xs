// JOB-1 (US-JOB-1-02) — Which tasks a job gets, from its pinned
// version. The backend twin of
// `webapp/protype-2/src/jobModel.ts::tasksFromVersion`.
//
// Verified byte-identical to the TypeScript on the golden fixture
// (UT-JOB-1-08/09): same three tasks, same order, same skip reason.
// Keep both sides in step — if one changes, the other must.
//
// One task per stage's OWNING row, plus any other row in that stage
// that both does planned work and has a task written in it. A stage
// whose owner does no planned work produces nothing and is REPORTED,
// never silently dropped — otherwise a job quietly has fewer tasks
// than its map implies and nobody knows which stage went missing.
//
// ORDER IS THE VERSION'S STAGE ORDER, owner first within each stage,
// so a job's task list reads like the map.
//
// ⚠️ WHY IT IS BUILT IN TWO PHASES. Deciding eligibility needs a
// lookup ("does this row do planned work?"), and acting on a lookup
// means branching on a variable set earlier in the same loop
// iteration — which silently discards the branch's writes
// (CLAUDE.md). So:
//   phase 1 pushes every CANDIDATE with its eligibility as a FIELD,
//           unconditionally, so nothing can be lost;
//   phase 2 walks the stages and picks owners then extras, branching
//           only on fields of loop items.
// The second phase is what puts them in the right order; it cannot
// be done in one pass without the branch that breaks.
function "jobs/tasks_from_version" {
  input {
    json snapshot
  }

  stack {
    var $stages {
      value = $input.snapshot.stages
    }

    var $lenses {
      value = $input.snapshot.lenses
    }

    var $cells {
      value = $input.snapshot.cells
    }

    var $key {
      value = ""
    }

    // Which rows do planned work, and which rows exist at all.
    var $works {
      value = {}
    }

    var $lens_exists {
      value = {}
    }

    foreach ($lenses) {
      each as $l {
        var.update $key {
          value = $l.key
        }

        var.update $lens_exists {
          value = $lens_exists|set:$key:1
        }

        var.update $works {
          value = $works|set:$key:$l.does_planned_work
        }
      }
    }

    // --- phase 1: candidates, with eligibility as a field ----------
    var $candidates {
      value = []
    }

    var $skipped {
      value = []
    }

    foreach ($stages) {
      each as $s {
        var.update $key {
          value = $s.owner_lens_key
        }

        array.push $candidates {
          value = {
            stage_key : $s.key
            lens_key  : $s.owner_lens_key
            is_owner  : true
            owner_here: ($lens_exists|get:$key:null)
            works     : ($works|get:$key:null)
          }
        }
      }
    }

    var $extra_candidates {
      value = []
    }

    foreach ($cells) {
      each as $c {
        var.update $key {
          value = $c.lens_key
        }

        array.push $extra_candidates {
          value = {
            stage_key: $c.stage_key
            lens_key : $c.lens_key
            is_owner : false
            works    : ($works|get:$key:null)
            task     : ($c.task ?? "")
          }
        }
      }
    }

    // --- phase 2: walk the stages, owner first ---------------------
    var $tasks {
      value = []
    }

    foreach ($stages) {
      each as $s {
        foreach ($candidates) {
          each as $cand {
            conditional {
              if ($cand.stage_key == $s.key && $cand.lens_key != null && $cand.lens_key != "" && $cand.works == true) {
                array.push $tasks {
                  value = {stage_key: $cand.stage_key, lens_key: $cand.lens_key, is_owner: true}
                }
              }
            }

            conditional {
              if ($cand.stage_key == $s.key && ($cand.lens_key == null || $cand.lens_key == "")) {
                array.push $skipped {
                  value = {stage_key: $cand.stage_key, reason: "no_owner"}
                }
              }
            }

            conditional {
              if ($cand.stage_key == $s.key && $cand.lens_key != null && $cand.lens_key != "" && $cand.owner_here == null) {
                array.push $skipped {
                  value = {stage_key: $cand.stage_key, reason: "owner_lens_missing"}
                }
              }
            }

            conditional {
              if ($cand.stage_key == $s.key && $cand.owner_here != null && $cand.works != true) {
                array.push $skipped {
                  value = {stage_key: $cand.stage_key, reason: "owner_does_no_planned_work"}
                }
              }
            }
          }
        }

        foreach ($extra_candidates) {
          each as $x {
            conditional {
              if ($x.stage_key == $s.key && $x.works == true && $x.lens_key != $s.owner_lens_key && ($x.task|trim) != "") {
                array.push $tasks {
                  value = {stage_key: $x.stage_key, lens_key: $x.lens_key, is_owner: false}
                }
              }
            }
          }
        }
      }
    }
  }

  response = {
    tasks  : $tasks
    skipped: $skipped
  }
}
