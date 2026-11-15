// COP-2 stories 01/05/07/08 — the Approval levels tab for one business: every action type from
// the one catalogue (copilot/action_types), its level here, whether it is locked or person-only,
// its limit, whether a copilot tool uses it yet ("wired"), and a SUGGESTION to move it down one
// level when the owner has decided 5 or more of that type and changed 10% or fewer. The
// suggestion is only ever a suggestion: levels move only through POST copilot/level_set.
//
// journey_architecture_id 0 = maps outside any business. Any other id must be this account's
// business (same answer as "not found", E-COP-035). Account admins only.
query "copilot/levels" verb=GET {
  api_group = "Members & Accounts"
  auth = "user"

  input {
    int journey_architecture_id?
  }

  stack {
    function.run "usr/assert_team_admin" {
      input = {
        actor_user_id: $auth.id
        step         : "copilot/levels"
        entity_id    : $input.journey_architecture_id
      }
    } as $admin_user

    db.query journey_architecture {
      where = $db.journey_architecture.id == $input.journey_architecture_id
      return = {type: "single"}
      output = ["id", "account_id"]
    } as $arch

    var $arch_ok {
      value = ($input.journey_architecture_id == 0 || ($arch|get:"account_id":0) == $admin_user.account_id)
    }

    precondition ($arch_ok) {
      error_type = "notfound"
      error = "We couldn't find that business. (E-COP-035)"
    }

    function.run "copilot/action_types" {
      input = {}
    } as $cat

    var $rows {
      value = []
    }

    foreach ($cat.order) {
      each as $k {
        var $t {
          value = $cat.types|get:$k:null
        }

        function.run "copilot/action_level" {
          input = {
            journey_architecture_id: $input.journey_architecture_id
            action_type            : $k
            amount                 : 0
            has_amount             : false
          }
        } as $lv

        db.query copilot_action {
          where = $db.copilot_action.account_id == $admin_user.account_id && $db.copilot_action.journey_architecture_id == $input.journey_architecture_id && $db.copilot_action.action_type == $k && ($db.copilot_action.status == "approved" || $db.copilot_action.status == "edited" || $db.copilot_action.status == "executed" || $db.copilot_action.status == "rejected")
          return = {type: "count"}
        } as $decided

        db.query copilot_action {
          where = $db.copilot_action.account_id == $admin_user.account_id && $db.copilot_action.journey_architecture_id == $input.journey_architecture_id && $db.copilot_action.action_type == $k && $db.copilot_action.status == "edited"
          return = {type: "count"}
        } as $edited

        var $suggest {
          value = ($lv.locked == false && $lv.person_only == false && $lv.level != "own" && $decided >= 5 && ($edited * 10) <= $decided)
        }

        array.push $rows {
          value = {
            key         : $k
            name        : ($t|get:"name":$k)
            touches     : $lv.touches
            reversible  : $lv.reversible
            level       : $lv.level
            locked      : $lv.locked
            person_only : $lv.person_only
            has_limit   : $lv.has_limit
            limit_amount: $lv.limit_amount
            wired       : ($t|get:"wired":false)
            decided     : $decided
            edited      : $edited
            suggest_down: $suggest
          }
        }
      }
    }
  }

  response = {journey_architecture_id: $input.journey_architecture_id, types: $rows}
  tags = ["cop-2"]
}
