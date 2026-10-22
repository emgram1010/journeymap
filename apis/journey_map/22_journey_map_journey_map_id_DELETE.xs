// Delete a journey map, and everything that only exists because of it.
//
// US-DEL-1-01 (2026-10-18) — A MAP IN USE CANNOT BE DELETED.
//
// This used to succeed no matter what, leaving a plan or template
// silently claiming a map that no longer existed. Not hypothetical:
// map 205 was deleted from the app at 03:29 UTC on 2026-10-18, hours
// before this guard existed, and left a plan and two templates
// pointing at nothing. The symptom was never an error here — it was
// a confusing refusal days later, when someone tried to create a job
// and got "This plan doesn't use 'that map'".
//
// The rule is `journey/assert_map_unused`, shared with the
// architecture cascade (api 69) so there is only ever one idea of
// what "in use" means. The message NAMES the plan or template,
// because "something uses it" is not something anyone can act on.
//
// US-DEL-1-05 — OWNER OR ACCOUNT ADMIN. Maps became visible across
// the whole account on 2026-10-17 (O8), while this endpoint still
// checked `owner_user == auth.id` alone — so a Delete control
// appeared on teammates' maps and always failed with a bare "Access
// denied". An admin can now delete any map on the account, everyone
// else only their own, and the refusal says who can (E-DEL-002).
// The dependency check above still applies to admins.
//
// US-DEL-1-03 — THE MAP'S CONTENT GOES WITH IT, via
// `journey/delete_map_cascade` (also shared with api 69). Deleting
// the map row alone is what produced 583 orphaned cells, 78 lenses
// and 55 stages. Cascading is safe here ONLY because the check above
// runs first: the only maps that reach it are ones nothing
// references.
//
// US-DEL-1-02 — `journey_map_version` IS NOT TOUCHED, here or in the
// cascade. A job reads its instructions from that frozen snapshot
// rather than from the live map, which is the only reason deleting a
// map cannot break work already in flight. `historyTables.ts` fails
// the build on any `db.del` against it.
query "journey_map/{journey_map_id}" verb=DELETE {
  api_group = "journey-map"
  auth = "user"

  input {
    int journey_map_id? filters=min:1
    text correlation_id? filters=trim
  }

  stack {
    db.get journey_map {
      field_name = "id"
      field_value = $input.journey_map_id
    } as $existing

    precondition ($existing != null) {
      error_type = "notfound"
      error = "Not Found"
    }

    db.get user {
      field_name = "id"
      field_value = $auth.id
    } as $actor

    var $account_id {
      value = ($actor.account_id ?? 0)
    }

    var $is_owner {
      value = ($existing.owner_user == $auth.id)
    }

    // An admin may delete any map on their OWN account — never one
    // belonging to another account, which stays a flat "not found".
    var $is_account_admin {
      value = ($actor.role == "admin" && $account_id != 0 && $existing.account_id == $account_id)
    }

    precondition ($is_owner == true || $is_account_admin == true) {
      error_type = "accessdenied"
      error = "Only the person who created this map, or an account admin, can delete it. (E-DEL-002)"
    }

    function.run "journey/assert_map_unused" {
      input = {journey_map_id: $input.journey_map_id}
    } as $usage

    var $reject_msg {
      value = ""
    }

    conditional {
      if ($usage.reason == "in_use_by_plan") {
        var.update $reject_msg {
          value = "The plan '" ~ $usage.blocker_name ~ "' uses this map. Remove it there first. (E-DEL-001)"
        }
      }
    }

    conditional {
      if ($usage.reason == "in_use_by_template") {
        var.update $reject_msg {
          value = "The template '" ~ $usage.blocker_name ~ "' uses this map. Remove it there first. (E-DEL-001)"
        }
      }
    }

    conditional {
      if ($usage.reason == "has_jobs") {
        var.update $reject_msg {
          value = "Work has been done from this map, so it can't be deleted. (E-DEL-001)"
        }
      }
    }

    conditional {
      if ($usage.ok == false) {
        function.run "ops/log_event" {
          input = {
            feature       : "DEL-1"
            step          : "delete_map"
            outcome       : "rejected"
            severity      : "info"
            user_id       : $auth.id
            account_id    : $account_id
            entity_type   : "journey_map"
            entity_id     : $input.journey_map_id
            correlation_id: $input.correlation_id
            error_code    : "E-DEL-001"
            message       : "Map delete refused — something depends on it."
            metadata      : {
              reason        : $usage.reason
              blocker_name  : $usage.blocker_name
              plan_count    : $usage.plan_count
              template_count: $usage.template_count
              job_count     : $usage.job_count
            }
          }
        }
      }
    }

    precondition ($usage.ok == true) {
      error_type = "inputerror"
      error = $reject_msg
    }

    function.run "journey/delete_map_cascade" {
      input = {journey_map_id: $input.journey_map_id}
    } as $removed

    function.run "ops/log_event" {
      input = {
        feature       : "DEL-1"
        step          : "delete_map"
        outcome       : "success"
        severity      : "info"
        user_id       : $auth.id
        account_id    : $account_id
        entity_type   : "journey_map"
        entity_id     : $input.journey_map_id
        correlation_id: $input.correlation_id
        message       : "Journey map deleted with its content."
        metadata      : {
          title   : $existing.title
          by_admin: ($is_owner == false)
          removed : $removed
        }
      }
    }
  }

  response = {deleted: true, id: $input.journey_map_id, removed: $removed}
}
