// CAT-1 (US-CAT-1-03) — Hard delete. Admin-only, same gate as
// deactivate. See apis/catalog/*_item-type_item_type_id_DELETE.xs's
// header. E-CAT-005 (added in RATE-1's review pass): refused while any
// Items-cell line on this account's maps, or any published rate
// (stage_rate), still uses the method. Deactivate instead.
query "method/{method_id}" verb=DELETE {
  api_group = "catalog"
  auth = "user"

  input {
    int method_id filters=min:1
    text correlation_id? filters=trim
  }

  stack {
    function.run "catalog/resolve_actor" {
      input = {user_id: $auth.id}
    } as $actor

    function.run "catalog/assert_method" {
      input = {account_id: $actor.account_id, method_id: $input.method_id, user_id: $actor.user_id, step: "delete_method", correlation_id: $input.correlation_id}
    } as $guard

    var $reject_code {
      value = ""
    }

    var $reject_msg {
      value = ""
    }

    conditional {
      if ($actor.role != "admin") {
        var.update $reject_code {
          value = "E-CAT-012"
        }

        var.update $reject_msg {
          value = "Only an account admin can deactivate, reactivate or delete a catalog entry. (E-CAT-012)"
        }
      }
    }

    conditional {
      if ($reject_code != "") {
        function.run "ops/log_event" {
          input = {
            feature       : "CAT-1"
            step          : "delete_method"
            outcome       : "rejected"
            severity      : "info"
            user_id       : $actor.user_id
            account_id    : $actor.account_id
            entity_type   : "method"
            entity_id     : $input.method_id
            correlation_id: $input.correlation_id
            error_code    : $reject_code
            message       : "Method delete refused."
          }
        }
      }
    }

    precondition ($reject_code == "") {
      error_type = "accessdenied"
      error = $reject_msg
    }

    // RATE-1 (review finding #1) — E-CAT-005, the reference check CAT-1
    // deferred to ITEM-1/RATE-1. A hard delete is refused while anything
    // still names this entry; deactivate instead. Without this, an item
    // deleted from the catalog would sail past the publish gate's
    // inactive-item rule (there is no row left to be inactive) and get
    // pinned into a new version's stage_rate as a dead key.
    // Scoped to this account's maps and their versions; every count is a
    // plain query or arithmetic — no conditional inside a loop.
    db.query journey_map {
      where = $db.journey_map.account_id == $actor.account_id
      return = {type: "list"}
    } as $acct_maps

    var $acct_map_ids {
      value = [-1]
    }

    foreach ($acct_maps) {
      each as $acct_map {
        array.push $acct_map_ids {
          value = $acct_map.id
        }
      }
    }

    db.query journey_map_version {
      where = $db.journey_map_version.journey_map_id in $acct_map_ids
      return = {type: "list"}
    } as $acct_versions

    var $acct_version_ids {
      value = [-1]
    }

    foreach ($acct_versions) {
      each as $acct_version {
        array.push $acct_version_ids {
          value = $acct_version.id
        }
      }
    }

    var $ref_key {
      value = $guard.method.key ?? ""
    }

    db.query journey_lens {
      where = $db.journey_lens.journey_map in $acct_map_ids && $db.journey_lens.template_key == "items-v1"
      return = {type: "list"}
    } as $acct_items_lenses

    var $acct_items_lens_ids {
      value = [-1]
    }

    foreach ($acct_items_lenses) {
      each as $acct_items_lens {
        array.push $acct_items_lens_ids {
          value = $acct_items_lens.id
        }
      }
    }

    db.query journey_cell {
      where = $db.journey_cell.lens in $acct_items_lens_ids
      return = {type: "list"}
    } as $acct_items_cells

    var $draft_refs {
      value = 0
    }

    foreach ($acct_items_cells) {
      each as $acct_items_cell {
        var $ref_cell_lines {
          value = $acct_items_cell.actor_fields.lines ?? []
        }

        foreach ($ref_cell_lines) {
          each as $ref_line {
            var.update $draft_refs {
              value = $draft_refs + ((($ref_line.method_key ?? "") == $ref_key)|to_int)
            }
          }
        }
      }
    }

    db.query stage_rate {
      where = $db.stage_rate.journey_map_version_id in $acct_version_ids && $db.stage_rate.method_key == $ref_key
      return = {type: "count"}
    } as $rate_refs

    var $ref_total {
      value = $draft_refs + $rate_refs
    }

    conditional {
      if ($ref_total > 0) {
        function.run "ops/log_event" {
          input = {
            feature       : "CAT-1"
            step          : "delete_method"
            outcome       : "rejected"
            severity      : "info"
            user_id       : $actor.user_id
            account_id    : $actor.account_id
            entity_type   : "method"
            entity_id     : $input.method_id
            correlation_id: $input.correlation_id
            error_code    : "E-CAT-005"
            message       : "Method delete refused: still referenced."
            metadata      : {draft_refs: $draft_refs, rate_refs: $rate_refs}
          }
        }
      }
    }

    precondition ($ref_total == 0) {
      error_type = "inputerror"
      error = "This is used by a map or a published version. Deactivate it instead. (E-CAT-005)"
    }

    db.del method {
      field_name = "id"
      field_value = $input.method_id
    }

    function.run "ops/log_event" {
      input = {
        feature       : "CAT-1"
        step          : "delete_method"
        outcome       : "success"
        severity      : "info"
        user_id       : $actor.user_id
        account_id    : $actor.account_id
        entity_type   : "method"
        entity_id     : $input.method_id
        correlation_id: $input.correlation_id
        message       : "Method deleted."
      }
    }
  }

  response = {deleted: true, method_id: $input.method_id}
}
