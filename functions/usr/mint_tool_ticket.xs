// COP-1 — make a run ticket for an agent about to work for a signed-in person. Called by an endpoint (which knows $auth.id) just before ai.agent.run; the endpoint puts the returned ticket in the agent's context, next to turn_id, to be passed to every tool. The account is read here from the user row, never taken from input. Default life 30 minutes.
function "usr/mint_tool_ticket" {
  input {
    int user_id filters=min:1
    int journey_map_id?
    int journey_architecture_id?
    text source? filters=trim
    int ttl_seconds?
  }

  stack {
    db.query user {
      where = $db.user.id == $input.user_id
      return = {type: "single"}
      output = ["id", "account_id"]
    } as $user_row

    var $uid {
      value = $user_row|get:"id":0
    }

    precondition ($uid != 0) {
      error_type = "accessdenied"
      error = "We couldn't find your user record. (E-USR-010)"
    }

    var $account_id {
      value = $user_row|get:"account_id":0
    }

    var $ttl {
      value = 1800
    }

    conditional {
      if ($input.ttl_seconds != 0) {
        var.update $ttl {
          value = $input.ttl_seconds
        }
      }
    }

    var $now_ms {
      value = now|to_int
    }

    var $expires {
      value = $now_ms + ($ttl * 1000)
    }

    security.create_uuid as $ticket

    db.add tool_run_ticket {
      data = {
        ticket                 : $ticket
        user_id                : $uid
        account_id             : $account_id
        journey_map_id         : $input.journey_map_id
        journey_architecture_id: $input.journey_architecture_id
        expires_at             : $expires
        source                 : $input.source
      }
    } as $row
  }

  response = {ticket: $ticket, expires_at: $expires}
}
