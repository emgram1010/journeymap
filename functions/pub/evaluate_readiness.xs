// PUB-1 (US-PUB-1-01) — The server's own readiness check, over a
// snapshot from pub/build_map_snapshot.
//
// PARITY IS THE POINT: this must produce the same reason codes as
// webapp/protype-2/src/readiness.ts (AUTH-1), case for case, or the UI
// will say "ready" while the gate says no. The codes are the same stable
// identifiers; only this file turns them into sentences.
//
// Relies on the snapshot's own rule that cells[] contains ONLY cells on
// work-doing rows that have something in them — so "a cell is present"
// already means "this cell was started", which is exactly AUTH-1's
// hasAnyContent test, evaluated once in the snapshot builder.
//
// The extra "real title" rule from D-39 is NOT here: it belongs to the
// publish gate (pub/evaluate_gate), so this function stays a pure mirror
// of AUTH-1 and can be compared against its golden fixtures directly.
function "pub/evaluate_readiness" {
  description = "Server-side readiness over a map snapshot. Same reason codes as AUTH-1's readiness.ts."

  input {
    json snapshot {
      description = "From pub/build_map_snapshot."
    }
  }

  stack {
    var $blockers {
      value = []
    }

    var $warnings {
      value = []
    }

    var $title {
      value = $input.snapshot.title ?? ""
    }

    var $title_trimmed {
      value = $title|trim
    }

    conditional {
      if ($title_trimmed == "") {
        array.push $blockers {
          value = {
            code     : "NO_WORK_TYPE_NAME"
            stage_key: null
            lens_key : null
            message  : "Give this map a name."
          }
        }
      }
    }

    var $stages {
      value = $input.snapshot.stages ?? []
    }

    var $lenses {
      value = $input.snapshot.lenses ?? []
    }

    var $cells {
      value = $input.snapshot.cells ?? []
    }

    var $stage_count {
      value = $stages|count
    }

    conditional {
      if ($stage_count == 0) {
        array.push $blockers {
          value = {
            code     : "NO_STAGES"
            stage_key: null
            lens_key : null
            message  : "Add at least one stage."
          }
        }
      }
    }

    // Which rows do planned work, by key.
    var $works_by_lens {
      value = {}
    }

    foreach ($lenses) {
      each as $lens {
        var $lens_key_text {
          value = $lens.key ?? ""
        }

        var.update $works_by_lens {
          value = $works_by_lens|set:$lens_key_text:($lens.does_planned_work == true)
        }
      }
    }

    var $ready_count {
      value = 0
    }

    foreach ($stages) {
      each as $stage {
        var $stage_key {
          value = $stage.key ?? ""
        }

        var $stage_label {
          value = ($stage.label ?? "")|trim
        }

        var $stage_blockers {
          value = 0
        }

        conditional {
          if ($stage_label == "") {
            array.push $blockers {
              value = {
                code     : "NO_STAGE_NAME"
                stage_key: $stage_key
                lens_key : null
                message  : "This stage needs a name."
              }
            }

            var.update $stage_blockers {
              value = $stage_blockers + 1
            }
          }
        }

        var $owner_key {
          value = $stage.owner_lens_key ?? ""
        }

        conditional {
          if ($owner_key == "") {
            array.push $blockers {
              value = {
                code     : "NO_OWNER"
                stage_key: $stage_key
                lens_key : null
                message  : "Pick who owns this stage."
              }
            }

            var.update $stage_blockers {
              value = $stage_blockers + 1
            }
          }

          else {
            var $owner_works {
              value = $works_by_lens|get:$owner_key:false
            }

            conditional {
              if ($owner_works != true) {
                array.push $blockers {
                  value = {
                    code     : "OWNER_NOT_WORK_ROLE"
                    stage_key: $stage_key
                    lens_key : $owner_key
                    message  : "This stage's owner doesn't do planned work. Pick a different owner, or turn that row's switch on."
                  }
                }

                var.update $stage_blockers {
                  value = $stage_blockers + 1
                }
              }

              else {
                // The owner's cell must carry a task and a duration.
                var $owner_task {
                  value = ""
                }

                var $owner_minutes {
                  value = null
                }

                var $owner_done_when {
                  value = ""
                }

                var $owner_cell_found {
                  value = false
                }

                foreach ($cells) {
                  each as $cell {
                    conditional {
                      if ($cell.stage_key == $stage_key && $cell.lens_key == $owner_key) {
                        var.update $owner_cell_found {
                          value = true
                        }

                        var.update $owner_task {
                          value = ($cell.task ?? "")|trim
                        }

                        var.update $owner_minutes {
                          value = $cell.duration_minutes
                        }

                        var.update $owner_done_when {
                          value = ($cell.done_when ?? "")|trim
                        }
                      }
                    }
                  }
                }

                conditional {
                  if ($owner_task == "") {
                    array.push $blockers {
                      value = {
                        code     : "NO_TASK"
                        stage_key: $stage_key
                        lens_key : $owner_key
                        message  : "Say what the owner does at this stage."
                      }
                    }

                    var.update $stage_blockers {
                      value = $stage_blockers + 1
                    }
                  }
                }

                conditional {
                  if ($owner_minutes == null) {
                    array.push $blockers {
                      value = {
                        code     : "NO_DURATION"
                        stage_key: $stage_key
                        lens_key : $owner_key
                        message  : "Say how long the owner's work takes."
                      }
                    }

                    var.update $stage_blockers {
                      value = $stage_blockers + 1
                    }
                  }
                }

                conditional {
                  if ($owner_cell_found == true && $owner_done_when == "") {
                    array.push $warnings {
                      value = {
                        code     : "NO_DONE_WHEN"
                        stage_key: $stage_key
                        lens_key : $owner_key
                        message  : "Recommended: say how you know this stage is done."
                      }
                    }
                  }
                }
              }
            }
          }
        }

        // Any OTHER started work cell on this stage must be complete too.
        foreach ($cells) {
          each as $other_cell {
            conditional {
              if ($other_cell.stage_key == $stage_key && $other_cell.lens_key != $owner_key) {
                var $other_task {
                  value = ($other_cell.task ?? "")|trim
                }

                conditional {
                  if ($other_task == "" || $other_cell.duration_minutes == null) {
                    array.push $blockers {
                      value = {
                        code     : "PARTIAL_WORK_CELL"
                        stage_key: $stage_key
                        lens_key : $other_cell.lens_key
                        message  : "This row's cell was started but isn't finished — it needs both a task and a duration."
                      }
                    }

                    var.update $stage_blockers {
                      value = $stage_blockers + 1
                    }
                  }
                }
              }
            }
          }
        }

        conditional {
          if ($stage_blockers == 0) {
            var.update $ready_count {
              value = $ready_count + 1
            }
          }
        }
      }
    }

    var $blocker_count {
      value = $blockers|count
    }

    var $ready {
      value = ($blocker_count == 0 && $stage_count > 0)
    }
  }

  response = {
    ready      : $ready
    blockers   : $blockers
    warnings   : $warnings
    ready_count: $ready_count
    total      : $stage_count
  }
}
