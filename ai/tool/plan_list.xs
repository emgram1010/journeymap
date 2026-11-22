// DISC-1 story 01 (2026-11-21) — list the plans of ONE business, so an AI can find a plan by name
// instead of asking the owner for its id. READ-ONLY: the gate is called with kind "read", nothing
// is written except the gate's own tool-log row, and no approval is ever asked for.
// What is visible is decided by the rules that already exist, never copied here:
//   - one business only: the chat's, or the one an outside assistant names (copilot/work_business, E-COP-045);
//   - the caller needs the Planner grant, like a person (usr/assert_module_access);
//   - a plan is listed only if copilot/plan_in_business says it belongs to this business, which
//     also keeps every other account's plan out.
// Archived plans are hidden unless include_archived is true. At most 100 plans are returned.
tool plan_list {
  instructions = "List the plans in this business so you can find one by name. Returns each plan's id, name, planning window, archived flag, the maps it accepts, how many people are on it and how many jobs it holds. name_contains filters by part of the name (upper and lower case are ignored). Archived plans are left out unless include_archived is true: only include them when the owner asks about archived plans. At most 100 plans come back; if truncated is true, narrow it with name_contains. This only reads. Call plan_get next to see one plan's people, jobs and days before you change anything."

  input {
    text name_contains? filters=trim {
      description = "Optional. Part of the plan's name."
    }

    bool include_archived? {
      description = "Leave false. True also lists archived plans."
    }

    int journey_architecture_id? {
      description = "Only for an outside assistant (no ticket): the business (architecture id) to look in. Leave 0 in a copilot chat: the chat's business is used."
    }

    text ticket? filters=trim {
      description = "COP-1 run ticket from your context. If you were given one, pass it on every tool call exactly as given. Otherwise leave it empty."
    }
  }

  stack {
    function.run "journey/tool_gate" {
      input = {journey_map_id: 0, journey_architecture_id: $input.journey_architecture_id, ticket: $input.ticket, tool: "plan_list", kind: "read"}
    } as $cop1_gate

    var $gate_pin {
      value = $cop1_gate.pin_architecture_id ?? 0
    }

    var $gate_via {
      value = $cop1_gate.via ?? ""
    }

    var $gate_context {
      value = $cop1_gate.context ?? ""
    }

    var $caller_user {
      value = $cop1_gate.user_id ?? 0
    }

    var $caller_account {
      value = $cop1_gate.account_id ?? 0
    }

    function.run "copilot/work_business" {
      input = {pin: $gate_pin, via: $gate_via, context: $gate_context, named: $input.journey_architecture_id, account_id: $caller_account}
    } as $work_biz

    var $pin {
      value = $work_biz.business ?? 0
    }

    precondition ($pin != 0 && $caller_user != 0 && $caller_account != 0) {
      error_type = "inputerror"
      error = "This needs one business: use it in a copilot chat about a business or, from an outside assistant, pass journey_architecture_id. (E-COP-045)"
    }

    function.run "usr/assert_module_access" {
      input = {actor_user_id: $caller_user, module: "planning", or_module: "", step: "tool/plan_list"}
    } as $_plan_ok

    db.query planner_workspace {
      where = $db.planner_workspace.account_id == $caller_account && ($input.include_archived == true || $db.planner_workspace.is_archived == false)
      sort = {planner_workspace.created_at: "desc"}
      return = {type: "list"}
      output = ["id", "name", "planning_window_start", "planning_window_end", "is_archived"]
    } as $plans

    var $needle {
      value = $input.name_contains|lower
    }

    // -1 keeps "in" valid when there is nothing to list.
    var $ids {
      value = [-1]
    }

    var $rows {
      value = []
    }

    var $member_tally {
      value = {}
    }

    var $job_tally {
      value = {}
    }

    var $key {
      value = ""
    }

    var $nm_lower {
      value = ""
    }

    var $name_hit {
      value = false
    }

    var $keep {
      value = false
    }

    var $kept {
      value = 0
    }

    var $cur {
      value = 0
    }

    var $next {
      value = 0
    }

    // Pass 1: decide each plan (no branching here: a keep flag and a running rank are stored on
    // the row, and pass 3 branches on the row itself).
    foreach ($plans) {
      each as $w {
        function.run "copilot/plan_in_business" {
          input = {account_id: $caller_account, workspace_id: $w.id, architecture_id: $pin, user_id: $caller_user}
        } as $chk

        var.update $nm_lower {
          value = $w.name|lower
        }

        var.update $name_hit {
          value = ($needle == "" || ($nm_lower|contains:$needle))
        }

        var.update $keep {
          value = (((($chk|get:"ok":false) ?? false) == true) && $name_hit)
        }

        var.update $kept {
          value = $kept + ($keep|to_int)
        }

        var.update $key {
          value = "p:" ~ ($w.id|to_text)
        }

        var.update $member_tally {
          value = $member_tally|set:$key:0
        }

        var.update $job_tally {
          value = $job_tally|set:$key:0
        }

        array.push $ids {
          value = $w.id
        }

        array.push $rows {
          value = {id: $w.id, name: $w.name, window_start: $w.planning_window_start, window_end: $w.planning_window_end, archived: $w.is_archived, keep: $keep, rank: $kept}
        }
      }
    }

    // Pass 2: counts and map titles for every plan of the account in one query each.
    db.query planner_agent {
      where = $db.planner_agent.workspace_id in $ids
      return = {type: "list"}
      output = ["id", "workspace_id"]
    } as $agents

    foreach ($agents) {
      each as $a {
        var.update $key {
          value = "p:" ~ ($a.workspace_id|to_text)
        }

        var.update $cur {
          value = ($member_tally|get:$key:0) ?? 0
        }

        var.update $next {
          value = $cur + 1
        }

        var.update $member_tally {
          value = $member_tally|set:$key:$next
        }
      }
    }

    db.query work_item {
      where = $db.work_item.workspace_id in $ids
      return = {type: "list"}
      output = ["id", "workspace_id"]
    } as $jobs

    foreach ($jobs) {
      each as $j {
        var.update $key {
          value = "p:" ~ ($j.workspace_id|to_text)
        }

        var.update $cur {
          value = ($job_tally|get:$key:0) ?? 0
        }

        var.update $next {
          value = $cur + 1
        }

        var.update $job_tally {
          value = $job_tally|set:$key:$next
        }
      }
    }

    db.query planner_workspace_map {
      where = $db.planner_workspace_map.workspace_id in $ids
      return = {type: "list"}
      output = ["id", "workspace_id", "journey_map_id"]
    } as $links

    var $map_ids {
      value = [-1]
    }

    foreach ($links) {
      each as $l {
        array.push $map_ids {
          value = $l.journey_map_id
        }
      }
    }

    db.query journey_map {
      where = $db.journey_map.id in $map_ids && $db.journey_map.account_id == $caller_account
      return = {type: "list"}
      output = ["id", "title"]
    } as $map_rows

    var $titles {
      value = {}
    }

    foreach ($map_rows) {
      each as $m {
        var.update $key {
          value = "m:" ~ ($m.id|to_text)
        }

        var.update $titles {
          value = $titles|set:$key:$m.title
        }
      }
    }

    // Pass 3: branch on the row only.
    var $result {
      value = []
    }

    var $plan_maps {
      value = []
    }

    var $title {
      value = ""
    }

    var $members {
      value = 0
    }

    var $job_count {
      value = 0
    }

    foreach ($rows) {
      each as $r {
        conditional {
          if ($r.keep == true && $r.rank <= 100) {
            var.update $plan_maps {
              value = []
            }

            foreach ($links) {
              each as $l2 {
                conditional {
                  if ($l2.workspace_id == $r.id) {
                    var.update $key {
                      value = "m:" ~ ($l2.journey_map_id|to_text)
                    }

                    var.update $title {
                      value = ($titles|get:$key:null) ?? ""
                    }

                    array.push $plan_maps {
                      value = {journey_map_id: $l2.journey_map_id, title: $title}
                    }
                  }
                }
              }
            }

            var.update $key {
              value = "p:" ~ ($r.id|to_text)
            }

            var.update $members {
              value = ($member_tally|get:$key:null) ?? 0
            }

            var.update $job_count {
              value = ($job_tally|get:$key:null) ?? 0
            }

            array.push $result {
              value = {plan_id: $r.id, name: $r.name, window_start: $r.window_start, window_end: $r.window_end, archived: $r.archived, maps: $plan_maps, member_count: $members, job_count: $job_count}
            }
          }
        }
      }
    }

    var $truncated {
      value = $kept > 100
    }

    var $hint {
      value = ""
    }

    conditional {
      if ($truncated) {
        var.update $hint {
          value = "Only the first 100 plans are shown. Use name_contains to narrow it."
        }
      }
    }
  }

  response = {
    business_id: $pin
    count      : ($result|count)
    total      : $kept
    truncated  : $truncated
    hint       : $hint
    plans      : $result
  }
}
