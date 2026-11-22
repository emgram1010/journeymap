// TAG-1 — every tag change a person makes in the app, through one door: action is add, remove, rename or delete. Each action is one function in functions/tags, the same ones the AI tools call, so the rules cannot drift. A person typing a tag is not asked "did you mean" (reuse_check false); exact matches in any case are still reused. Rename onto an existing name and delete of a tag in use both answer first (merge_needed / confirm_needed) and change nothing until merge or confirm is true.
query map_tag_change verb=POST {
  api_group = "journey-map"
  auth = "user"

  input {
    text action filters=trim
    int journey_map_id?
    int map_tag_id?
    text name? filters=trim
    bool merge?
    bool confirm?
  }

  stack {
    function.run "planner/resolve_actor" {
      input = {user_id: $auth.id}
    } as $actor

    var $acct {
      value = $actor.account_id ?? 0
    }

    precondition ($input.action == "add" || $input.action == "remove" || $input.action == "rename" || $input.action == "delete") {
      error_type = "inputerror"
      error = "action is add, remove, rename or delete."
    }

    var $result {
      value = {}
    }

    conditional {
      if ($input.action == "add") {
        function.run "tags/add_to_map" {
          input = {account_id: $acct, user_id: $auth.id, journey_map_id: $input.journey_map_id, name: $input.name, reuse_check: false, create_new: true}
        } as $r_add

        var.update $result {
          value = $r_add
        }
      }

      elseif ($input.action == "remove") {
        function.run "tags/remove_from_map" {
          input = {account_id: $acct, user_id: $auth.id, journey_map_id: $input.journey_map_id, map_tag_id: $input.map_tag_id, name: $input.name}
        } as $r_remove

        var.update $result {
          value = $r_remove
        }
      }

      elseif ($input.action == "rename") {
        function.run "tags/rename_tag" {
          input = {account_id: $acct, user_id: $auth.id, map_tag_id: $input.map_tag_id, name: $input.name, merge: $input.merge}
        } as $r_rename

        var.update $result {
          value = $r_rename
        }
      }

      else {
        function.run "tags/delete_tag" {
          input = {account_id: $acct, user_id: $auth.id, map_tag_id: $input.map_tag_id, confirm: $input.confirm}
        } as $r_delete

        var.update $result {
          value = $r_delete
        }
      }
    }
  }

  response = $result
}
