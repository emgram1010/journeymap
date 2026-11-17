// COP-5 story 05 - one scheduled-run tick for ONE account that has a copilot. Scheduled work is OFF for a business unless the owner set the approval level scheduled_work to run (own or tell) on the levels screen; an account with no such business writes nothing and answers enabled false. Otherwise: a switched-off copilot gets one "skipped" row; else it finds the copilot tasks on published days today (the same perform/* functions the performer app uses) and runs copilot/run_for_business for each switched-on business, which always writes exactly one row - so a switched-on business gets a row every tick, even with nothing to do. COP-8 story 02: a business that is soft-deleted (journey_architecture_deleted), gone, or not in this account is left out before any run (no row, no AI call) and counted in skipped_deleted; its level row is kept so a restore brings it back. The per-business work lives in its own function so that no conditional sits inside a loop here.
function "copilot/run_for_account" {
  input {
    int account_id
    int copilot_user_id
    text trigger? filters=trim
  }

  stack {
    var $trigger {
      value = "schedule"
    }

    conditional {
      if ($input.trigger == "manual") {
        var.update $trigger {
          value = "manual"
        }
      }
    }

    // COP-8 story 02 (R17): only businesses that still exist in this account and are not
    // soft-deleted. The level row itself is KEPT, so a restore brings the business back exactly as
    // it was. Both id lists start with a -1 sentinel so neither is ever empty (CLAUDE.md: not in []
    // is untested); "not in" is the confirmed form, never !(... in ...).
    db.query journey_architecture {
      where = $db.journey_architecture.account_id == $input.account_id && $input.account_id != 0
      return = {type: "list"}
      output = ["id"]
    } as $arch_rows

    var $live_arch_ids {
      value = [-1]
    }

    foreach ($arch_rows) {
      each as $ar {
        array.push $live_arch_ids {
          value = $ar.id
        }
      }
    }

    db.query journey_architecture_deleted {
      where = $db.journey_architecture_deleted.journey_architecture_id in $live_arch_ids
      return = {type: "list"}
      output = ["journey_architecture_id"]
    } as $deleted_rows

    var $deleted_arch_ids {
      value = [-1]
    }

    foreach ($deleted_rows) {
      each as $dr {
        array.push $deleted_arch_ids {
          value = $dr.journey_architecture_id
        }
      }
    }

    // Every switched-on level row, before the filter - only to count what was skipped.
    db.query copilot_action_level {
      where = $db.copilot_action_level.account_id == $input.account_id && $db.copilot_action_level.action_type == "scheduled_work" && ($db.copilot_action_level.level == "own" || $db.copilot_action_level.level == "tell") && $db.copilot_action_level.journey_architecture_id != 0
      return = {type: "count"}
    } as $on_all_count

    // Businesses of this account where scheduled work is switched on. (The default is "wait" = off,
    // so "on" always means a stored level row; run_for_business re-checks through copilot/action_level.)
    db.query copilot_action_level {
      where = $db.copilot_action_level.account_id == $input.account_id && $db.copilot_action_level.action_type == "scheduled_work" && ($db.copilot_action_level.level == "own" || $db.copilot_action_level.level == "tell") && $db.copilot_action_level.journey_architecture_id != 0 && $db.copilot_action_level.journey_architecture_id in $live_arch_ids && $db.copilot_action_level.journey_architecture_id not in $deleted_arch_ids
      sort = {copilot_action_level.journey_architecture_id: "asc"}
      return = {type: "list"}
      output = ["journey_architecture_id"]
    } as $on_rows

    var $on_count {
      value = $on_rows|count
    }

    // Switched on, but the business is soft-deleted, gone, or no longer in this account.
    var $skipped_deleted {
      value = $on_all_count - $on_count
    }

    var $enabled {
      value = ($on_count > 0) && ($input.account_id != 0) && ($input.copilot_user_id != 0)
    }

    db.query user_status {
      where = $db.user_status.user_id == $input.copilot_user_id
      return = {type: "single"}
    } as $cop_status

    // No row means active; an explicit false means switched off.
    var $is_active_raw {
      value = $cop_status|get:"is_active":true
    }

    var $switched_off {
      value = ($is_active_raw == false)
    }

    var $go {
      value = ($enabled == true) && ($switched_off == false)
    }

    var $off_row {
      value = ($enabled == true) && ($switched_off == true)
    }

    var $rows_written {
      value = 0
    }

    var $runs {
      value = 0
    }

    var $now_ms {
      value = now|to_int
    }

    security.create_uuid as $uid

    var $skip_key {
      value = "skip::" ~ $uid
    }

    var $date {
      value = ""
    }

    conditional {
      if ($off_row == true) {
        db.add copilot_run {
          data = {
            account_id             : $input.account_id
            journey_architecture_id: 0
            copilot_user_id        : $input.copilot_user_id
            trigger                : $trigger
            status                 : "skipped"
            lock_key               : $skip_key
            started_at             : $now_ms
            finished_at            : $now_ms
            reason                 : "The copilot is switched off, so it did not run."
          }
        } as $_off_added

        var.update $rows_written {
          value = 1
        }
      }
    }

    conditional {
      if ($go == true) {
        function.run "perform/today_for" {
          input = {user_id: $input.copilot_user_id, tz: ""}
        } as $today

        var.update $date {
          value = $today.date
        }

        function.run "perform/resolve_agents" {
          input = {account_id: $input.account_id, user_id: $input.copilot_user_id}
        } as $resolved

        function.run "perform/collect_published_items" {
          input = {account_id: $input.account_id, date: $today.date, agent_ids: $resolved.agent_ids}
        } as $collected

        var $wt_ids {
          value = []
        }

        foreach ($collected.items) {
          each as $i {
            foreach ($i.work_task_ids) {
              each as $wid {
                array.push $wt_ids {
                  value = $wid
                }
              }
            }
          }
        }

        foreach ($on_rows) {
          each as $b {
            function.run "copilot/run_for_business" {
              input = {account_id: $input.account_id, journey_architecture_id: $b.journey_architecture_id, copilot_user_id: $input.copilot_user_id, work_task_ids: $wt_ids, date: $today.date, trigger: $trigger}
            } as $r

            var.update $rows_written {
              value = $rows_written + $r.rows_written
            }

            var.update $runs {
              value = $runs + (($r.status == "finished")|to_int) + (($r.status == "failed")|to_int)
            }
          }
        }
      }
    }
  }

  response = {enabled: $enabled, businesses_on: $on_count, skipped_deleted: $skipped_deleted, switched_off: $switched_off, rows_written: $rows_written, runs: $runs}
}
