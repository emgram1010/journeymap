// DEMAND-1 story 03 — turn ONE order from an outside system into a job, exactly once. Called by orders/ingest (after the key is checked) and by the retry of held or unrouted orders. Only structured fields are read: id, order number, status, two dates, fulfilment type and lines of {external_id, name, quantity}. A customer note or any other free text is never read, stored or shown to an AI. Rules, in order: orders paused for the account are held; no matching routing rule = no_route (nothing is added, it is listed for the owner); a new order inserts its claim row FIRST (the unique index on account + source + order id decides a race; the loser is a duplicate), then the job is made with its items through the same rule a person's job uses (planner_ops/create_work_item) and lands in the plan's backlog flagged unplanned. An order seen before: unchanged = duplicate; cancelled, or changed after work started = the job is flagged and nothing else is touched; changed before work started = its items are replaced. It never creates a day, never publishes, and never moves planned work. Every outcome writes an order_inbox row and an event.
function "orders/process" {
  input {
    int account_id
    text source_system? filters=trim
    json order?
  }

  stack {
    var $acct {
      value = $input.account_id
    }

    var $source {
      value = ($input.source_system ?? "")|trim|lower
    }

    var $o {
      value = $input.order ?? {}
    }

    var $ext {
      value = ((($o|get:"external_id":"") ?? "")|to_text)|trim|substr:0:120
    }

    var $number_raw {
      value = ((($o|get:"order_number":"") ?? "")|to_text)|trim|substr:0:40
    }

    var $order_number {
      value = $number_raw|replace:"<":""|replace:">":""
    }

    var $status {
      value = ((($o|get:"status":"") ?? "")|to_text)|trim|lower
    }

    var $fulfil_raw {
      value = ((($o|get:"fulfilment":"") ?? "")|to_text)|trim|lower|substr:0:40
    }

    var $fulfilment {
      value = $fulfil_raw|replace:"<":""|replace:">":""
    }

    var $starts_raw {
      value = ((($o|get:"starts_on":"") ?? "")|to_text)|trim|substr:0:10
    }

    var $ends_raw {
      value = ((($o|get:"ends_on":"") ?? "")|to_text)|trim|substr:0:10
    }

    var $starts_ok {
      value = "/^[0-9]{4}-[0-9]{2}-[0-9]{2}$/"|regex_matches:$starts_raw
    }

    var $ends_ok {
      value = "/^[0-9]{4}-[0-9]{2}-[0-9]{2}$/"|regex_matches:$ends_raw
    }

    var $starts_on {
      value = ""
    }

    var $ends_on {
      value = ""
    }

    conditional {
      if ($starts_ok) {
        var.update $starts_on {
          value = $starts_raw
        }
      }
    }

    conditional {
      if ($ends_ok) {
        var.update $ends_on {
          value = $ends_raw
        }
      }
    }

    var $cancelled {
      value = ($status == "cancelled" || $status == "canceled")
    }

    var $lines_in {
      value = ($o|get:"lines":null) ?? []
    }

    // What is kept of the order: structured fields only.
    var $kept {
      value = {external_id: $ext, order_number: $order_number, status: $status, fulfilment: $fulfilment, starts_on: $starts_on, ends_on: $ends_on, lines: $lines_in}
    }

    var $outcome {
      value = ""
    }

    var $detail {
      value = ""
    }

    var $job_id {
      value = 0
    }

    var $line_count {
      value = 0
    }

    var $unmatched_count {
      value = 0
    }

    db.query account_ai_pause {
      where = $db.account_ai_pause.account_id == $acct
      return = {type: "single"}
    } as $pause_row

    var $paused {
      value = ($pause_row|get:"is_paused":false) == true
    }

    // The routing rule: an exact fulfilment match wins over the catch-all (empty match).
    db.query order_route {
      where = $db.order_route.account_id == $acct && $db.order_route.source_system == $source && $db.order_route.is_enabled == true && $db.order_route.workspace_id != 0
      return = {type: "list"}
    } as $routes

    var $exact_id {
      value = 0
    }

    var $any_id {
      value = 0
    }

    var $hit {
      value = 0
    }

    foreach ($routes) {
      each as $r {
        var.update $hit {
          value = ($r.match_fulfilment == $fulfilment && $fulfilment != "")|to_int
        }

        var.update $exact_id {
          value = $exact_id + (($r.id - $exact_id) * $hit)
        }

        var.update $hit {
          value = ($r.match_fulfilment == "")|to_int
        }

        var.update $any_id {
          value = $any_id + (($r.id - $any_id) * $hit)
        }
      }
    }

    var $route_id {
      value = $exact_id
    }

    conditional {
      if ($route_id == 0) {
        var.update $route_id {
          value = $any_id
        }
      }
    }

    db.query order_route {
      where = $db.order_route.id == $route_id && $route_id != 0
      return = {type: "single"}
    } as $route

    var $plan_id {
      value = $route|get:"workspace_id":0
    }

    var $map_id {
      value = $route|get:"journey_map_id":0
    }

    var $route_user {
      value = $route|get:"created_by_user_id":0
    }

    db.query work_item_origin {
      where = $db.work_item_origin.account_id == $acct && $db.work_item_origin.source_system == $source && $db.work_item_origin.external_id == $ext
      return = {type: "single"}
    } as $origin

    var $origin_id {
      value = $origin|get:"id":0
    }

    var $origin_job {
      value = $origin|get:"work_item_id":0
    }

    conditional {
      if ($ext == "" || $source == "" || $acct == 0) {
        var.update $outcome {
          value = "refused"
        }

        var.update $detail {
          value = "The order has no id. (E-HOOK-003)"
        }
      }

      elseif ($paused) {
        var.update $outcome {
          value = "held"
        }

        var.update $detail {
          value = "AI and incoming orders are paused for this account. The order is kept and can be retried."
        }
      }

      elseif ($origin_id == 0 && $cancelled) {
        var.update $outcome {
          value = "duplicate"
        }

        var.update $detail {
          value = "Cancelled before it was ever added. Nothing to do."
        }
      }

      elseif ($origin_id == 0 && $route_id == 0) {
        var.update $outcome {
          value = "no_route"
        }

        var.update $detail {
          value = "No routing rule matches this order, so nothing was added. (E-HOOK-004)"
        }
      }

      elseif ($origin_id != 0 && $origin_job == 0) {
        var.update $outcome {
          value = "duplicate"
        }

        var.update $detail {
          value = "This order is already being added."
        }
      }
    }

    // From here the order needs its lines: which catalog items, how many.
    var $needs_lines {
      value = $outcome == ""
    }

    var $lines {
      value = []
    }

    var $unmatched {
      value = []
    }

    var $fingerprint {
      value = ""
    }

    var $lines_map {
      value = $map_id
    }

    conditional {
      if ($needs_lines && $origin_id != 0) {
        db.query work_item {
          where = $db.work_item.id == $origin_job
          return = {type: "single"}
          output = ["id", "journey_map_version_id"]
        } as $old_job

        var $old_version_id {
          value = $old_job|get:"journey_map_version_id":0
        }

        db.query journey_map_version {
          where = $db.journey_map_version.id == $old_version_id
          return = {type: "single"}
          output = ["id", "journey_map_id"]
        } as $old_version

        var.update $lines_map {
          value = $old_version|get:"journey_map_id":0
        }
      }
    }

    conditional {
      if ($needs_lines) {
        function.run "items/resolve_external" {
          input = {account_id: $acct, source_system: $source, products: $lines_in, remember: true}
        } as $ext_items

        function.run "estimate/resolve_item_lines" {
          input = {account_id: $acct, journey_map_id: $lines_map, items: $ext_items.items}
        } as $resolved

        conditional {
          if ($resolved.ok != true) {
            var.update $outcome {
              value = "refused"
            }

            var.update $detail {
              value = $resolved.message
            }
          }
        }

        var.update $lines {
          value = $resolved.lines
        }

        foreach ($resolved.lines) {
          each as $rl {
            var.update $fingerprint {
              value = $fingerprint ~ $rl.item_key ~ "::" ~ ($rl.quantity|to_text) ~ ";"
            }
          }
        }

        foreach ($resolved.unknown_items) {
          each as $ui {
            array.push $unmatched {
              value = {source_system: $source, external_id: "", label: $ui.item_key, quantity: $ui.quantity, reason: "unknown_item"}
            }
          }
        }

        foreach ($ext_items.unlinked) {
          each as $ul {
            array.push $unmatched {
              value = {source_system: $source, external_id: $ul.external_id, label: $ul.name, quantity: $ul.quantity, reason: "unlinked_product"}
            }

            var.update $fingerprint {
              value = $fingerprint ~ "x:" ~ $ul.external_id ~ "::" ~ ($ul.quantity|to_text) ~ ";"
            }
          }
        }

        var.update $line_count {
          value = $lines|count
        }

        var.update $unmatched_count {
          value = $unmatched|count
        }
      }
    }

    // A new order: claim first, then make the job.
    conditional {
      if ($outcome == "" && $origin_id == 0) {
        var $claimed {
          value = false
        }

        try_catch {
          try {
            db.add work_item_origin {
              data = {created_at: "now", updated_at: "now", account_id: $acct, work_item_id: 0, source_system: $source, external_id: $ext, order_number: $order_number, starts_on: $starts_on, ends_on: $ends_on, fulfilment: $fulfilment, is_unplanned: true, order_flag: "none", lines_fingerprint: $fingerprint}
            } as $claim

            var.update $claimed {
              value = true
            }

            var.update $origin_id {
              value = $claim.id
            }
          }

          catch {
            var.update $claimed {
              value = false
            }
          }
        }

        conditional {
          if ($claimed == false) {
            var.update $outcome {
              value = "duplicate"
            }

            var.update $detail {
              value = "The same order arrived twice at once. One job was made."
            }
          }

          else {
            var $title_number {
              value = $order_number
            }

            conditional {
              if ($title_number == "") {
                var.update $title_number {
                  value = $ext|replace:"<":""|replace:">":""
                }
              }
            }

            var $title_full {
              value = "Order #" ~ $title_number ~ " " ~ $fulfilment ~ " " ~ $starts_on
            }

            var $title {
              value = ($title_full|trim)|substr:0:120
            }

            function.run "planner/resolve_actor" {
              input = {user_id: $route_user}
            } as $actor

            try_catch {
              try {
                function.run "planner_ops/create_work_item" {
                  input = {actor: $actor, workspace_id: $plan_id, journey_map_id: $map_id, title: $title, attributes: {}, parent_work_item_id: 0, correlation_id: "", order_lines: $lines, unmatched_lines: $unmatched}
                } as $created

                var.update $job_id {
                  value = $created.work_item.id
                }

                db.patch work_item_origin {
                  field_name = "id"
                  field_value = $origin_id
                  data = {work_item_id: $job_id, updated_at: "now"}
                } as $claim_done

                var.update $outcome {
                  value = "created"
                }
              }

              catch {
                var $caught {
                  value = $error
                }

                var.update $detail {
                  value = ($caught|get:"message":"The job could not be made.") ?? "The job could not be made."
                }

                var.update $outcome {
                  value = "failed"
                }

                // Give the claim back, so a retry can add the order.
                db.del work_item_origin {
                  field_name = "id"
                  field_value = $origin_id
                }
              }
            }
          }
        }
      }
    }

    // An order seen before.
    conditional {
      if ($outcome == "" && $origin_id != 0 && $job_id == 0) {
        var.update $job_id {
          value = $origin_job
        }

        db.query work_task {
          where = $db.work_task.work_item_id == $origin_job && $db.work_task.status != "not_started"
          return = {type: "count"}
        } as $started

        var $old_print {
          value = ($origin|get:"lines_fingerprint":"") ?? ""
        }

        var $old_flag {
          value = ($origin|get:"order_flag":"none") ?? "none"
        }

        conditional {
          if ($cancelled && $old_flag != "order_cancelled") {
            db.patch work_item_origin {
              field_name = "id"
              field_value = $origin_id
              data = {order_flag: "order_cancelled", updated_at: "now"}
            } as $flag_cancel

            var.update $outcome {
              value = "flagged"
            }

            var.update $detail {
              value = "The order was cancelled. The job is flagged for a person; started work is not changed."
            }
          }

          elseif ($cancelled || $old_print == $fingerprint) {
            var.update $outcome {
              value = "duplicate"
            }

            var.update $detail {
              value = "Nothing changed."
            }
          }

          elseif ($started > 0) {
            db.patch work_item_origin {
              field_name = "id"
              field_value = $origin_id
              data = {order_flag: "order_changed", updated_at: "now"}
            } as $flag_change

            var.update $outcome {
              value = "flagged"
            }

            var.update $detail {
              value = "The order changed after work started. The job is flagged for a person; its items were not changed."
            }
          }

          else {
            db.query work_item_line {
              where = $db.work_item_line.work_item_id == $origin_job
              return = {type: "list"}
            } as $old_lines

            db.query work_item_unmatched_line {
              where = $db.work_item_unmatched_line.work_item_id == $origin_job
              return = {type: "list"}
            } as $old_unmatched

            db.transaction {
              stack {
                foreach ($old_lines) {
                  each as $ol {
                    db.del work_item_line {
                      field_name = "id"
                      field_value = $ol.id
                    }
                  }
                }

                foreach ($old_unmatched) {
                  each as $ou {
                    db.del work_item_unmatched_line {
                      field_name = "id"
                      field_value = $ou.id
                    }
                  }
                }

                foreach ($lines) {
                  each as $nl {
                    db.add work_item_line {
                      data = {created_at: "now", work_item_id: $origin_job, item_type_id: $nl.item_type_id, quantity: $nl.quantity, flagged_quantity: 0, created_by: $route_user}
                    } as $nl_added
                  }
                }

                foreach ($unmatched) {
                  each as $nu {
                    db.add work_item_unmatched_line {
                      data = {created_at: "now", account_id: $acct, work_item_id: $origin_job, source_system: $nu.source_system, external_id: $nu.external_id, label: $nu.label, quantity: $nu.quantity, reason: $nu.reason}
                    } as $nu_added
                  }
                }

                db.patch work_item_origin {
                  field_name = "id"
                  field_value = $origin_id
                  data = {lines_fingerprint: $fingerprint, order_number: $order_number, starts_on: $starts_on, ends_on: $ends_on, updated_at: "now"}
                } as $print_saved
              }
            }

            var.update $outcome {
              value = "updated"
            }

            var.update $detail {
              value = "The order changed before work started. The job's items were updated."
            }
          }
        }
      }
    }

    var $severity {
      value = "info"
    }

    conditional {
      if ($outcome == "failed" || $outcome == "no_route" || $outcome == "flagged" || $outcome == "refused") {
        var.update $severity {
          value = "warn"
        }
      }
    }

    var $ev_outcome {
      value = "success"
    }

    conditional {
      if ($outcome == "failed") {
        var.update $ev_outcome {
          value = "failure"
        }
      }

      elseif ($outcome == "no_route" || $outcome == "refused" || $outcome == "held") {
        var.update $ev_outcome {
          value = "rejected"
        }
      }
    }

    db.add order_inbox {
      data = {created_at: "now", account_id: $acct, source_system: $source, external_id: $ext, order_number: $order_number, order_status: $status, outcome: $outcome, detail: $detail, work_item_id: $job_id, line_count: $line_count, unmatched_count: $unmatched_count, payload: $kept}
    } as $inbox

    var $step {
      value = "order_" ~ $outcome
    }

    function.run "ops/log_event" {
      input = {feature: "DEMAND-1", step: $step, outcome: $ev_outcome, severity: $severity, error_code: "", message: $detail, user_id: 0, account_id: $acct, entity_type: "work_item", entity_id: $job_id, correlation_id: "", duration_ms: 0, metadata: {source_system: $source, order_inbox_id: $inbox.id, line_count: $line_count, unmatched_count: $unmatched_count}}
    } as $_ev
  }

  response = {outcome: $outcome, detail: $detail, work_item_id: $job_id, order_inbox_id: $inbox.id, line_count: $line_count, unmatched_count: $unmatched_count}
}
