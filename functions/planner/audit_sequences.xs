// PLN-8 (US-PLN-8-02) — The seq invariant. Read-only.
//
// Code: SEQ_GAP_OR_DUP — a container whose seq is not exactly 1..n.
//
// CHECKED EXACTLY, NOT BY CHECKSUM. Summing the seqs and comparing to
// n(n+1)/2 looks tempting and is wrong: [1,1,4,4] sums to 10, the
// same as [1,2,3,4], so the most likely real corruption — a duplicate
// position — would pass. Each task's seq is compared to the position
// it should hold.
//
// Containers are discovered from the tasks themselves, deduplicated
// through a seen-map, so an empty timeline is trivially fine and
// needs no query.
//
// Two passes, for the reason in planner/audit_agents: the position
// counter is recorded as a FIELD in pass 1 and compared against the
// loop item's own seq in pass 2.
function "planner/audit_sequences" {
  input {
    int account_id filters=min:1
  }

  stack {
    db.query planner_workspace {
      where = $db.planner_workspace.account_id == $input.account_id
      return = {type: "list"}
    } as $workspaces

    var $ws_ids {
      value = []
    }

    foreach ($workspaces) {
      each as $w {
        array.push $ws_ids {
          value = $w.id
        }
      }
    }

    var $violations {
      value = []
    }

    var $key {
      value = ""
    }

    var $part_a {
      value = ""
    }

    var $part_b {
      value = ""
    }

    conditional {
      if (($ws_ids|count) > 0) {
        db.query planner_task {
          where = $db.planner_task.workspace_id in $ws_ids
          return = {type: "list"}
        } as $tasks

        var $seen {
          value = {}
        }

        var $container_rows {
          value = []
        }

        foreach ($tasks) {
          each as $tk {
            var.update $part_a {
              value = $tk.workspace_id|to_text
            }

            var.update $part_b {
              value = $tk.timeline_id|to_text
            }

            var.update $key {
              value = $part_a ~ "-" ~ $part_b
            }

            array.push $container_rows {
              value = {
                key         : $key
                workspace_id: $tk.workspace_id
                timeline_id : $tk.timeline_id
                already     : ($seen|get:$key:null)
              }
            }

            var.update $seen {
              value = $seen|set:$key:1
            }
          }
        }

        var $seq_checks {
          value = []
        }

        var $pos {
          value = 0
        }

        foreach ($container_rows) {
          each as $c {
            conditional {
              if ($c.already == null) {
                db.query planner_task {
                  where = $db.planner_task.workspace_id == $c.workspace_id && $db.planner_task.timeline_id == $c.timeline_id
                  sort = {planner_task.seq: "asc", planner_task.id: "asc"}
                  return = {type: "list"}
                } as $container_tasks

                var.update $pos {
                  value = 0
                }

                foreach ($container_tasks) {
                  each as $ct {
                    var.update $pos {
                      value = $pos + 1
                    }

                    array.push $seq_checks {
                      value = {container: $c.key, id: $ct.id, seq: $ct.seq, expected: $pos}
                    }
                  }
                }
              }
            }
          }
        }

        foreach ($seq_checks) {
          each as $s {
            conditional {
              if ($s.seq != $s.expected) {
                array.push $violations {
                  value = {code: "SEQ_GAP_OR_DUP", entity: "planner_task", id: $s.id, detail: $s.container}
                }
              }
            }
          }
        }
      }
    }
  }

  response = {violations: $violations}
}
