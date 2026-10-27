// CAT-1 (US-CAT-1-03) — Hard delete. Admin-only, same gate as
// deactivate (D-1's "only an admin can deactivate" is read here as "at
// least that restrictive for delete too" -- delete is more destructive,
// never less).
//
// E-CAT-005 (added in RATE-1's review pass): refused while a map's item
// list (journey_lens_item) or a published rate (stage_rate, this
// account's versions) still references the item. Deactivate instead.
query "item-type/{item_type_id}" verb=DELETE {
  api_group = "catalog"
  auth = "user"

  input {
    int item_type_id filters=min:1
    text correlation_id? filters=trim
  }

  stack {
    function.run "catalog/resolve_actor" {
      input = {user_id: $auth.id}
    } as $actor

    function.run "catalog/assert_item_type" {
      input = {account_id: $actor.account_id, item_type_id: $input.item_type_id, user_id: $actor.user_id, step: "delete_item_type", correlation_id: $input.correlation_id}
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
            step          : "delete_item_type"
            outcome       : "rejected"
            severity      : "info"
            user_id       : $actor.user_id
            account_id    : $actor.account_id
            entity_type   : "item_type"
            entity_id     : $input.item_type_id
            correlation_id: $input.correlation_id
            error_code    : $reject_code
            message       : "Item type delete refused."
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
      value = $guard.item.key ?? ""
    }

    db.query journey_lens_item {
      where = $db.journey_lens_item.item_type_id == $input.item_type_id
      return = {type: "count"}
    } as $draft_refs

    db.query stage_rate {
      where = $db.stage_rate.journey_map_version_id in $acct_version_ids && $db.stage_rate.quantity_key == $ref_key
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
            step          : "delete_item_type"
            outcome       : "rejected"
            severity      : "info"
            user_id       : $actor.user_id
            account_id    : $actor.account_id
            entity_type   : "item_type"
            entity_id     : $input.item_type_id
            correlation_id: $input.correlation_id
            error_code    : "E-CAT-005"
            message       : "Item type delete refused: still referenced."
            metadata      : {draft_refs: $draft_refs, rate_refs: $rate_refs}
          }
        }
      }
    }

    precondition ($ref_total == 0) {
      error_type = "inputerror"
      error = "This is used by a map or a published version. Deactivate it instead. (E-CAT-005)"
    }

    db.del item_type {
      field_name = "id"
      field_value = $input.item_type_id
    }

    function.run "ops/log_event" {
      input = {
        feature       : "CAT-1"
        step          : "delete_item_type"
        outcome       : "success"
        severity      : "info"
        user_id       : $actor.user_id
        account_id    : $actor.account_id
        entity_type   : "item_type"
        entity_id     : $input.item_type_id
        correlation_id: $input.correlation_id
        message       : "Item type deleted."
      }
    }
  }

  response = {deleted: true, item_type_id: $input.item_type_id}
}
