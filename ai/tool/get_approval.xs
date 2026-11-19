// COP-2 review fix — the copilot reads one of its own approval items: its status and, once the owner has approved or edited it, the exact input it may now run with (approved_payload). Without this the copilot could never learn that an item was approved, or what the owner's edited version says. Same account only (another account's item answers "not found"). Read-only; goes through the gate like every tool.
tool get_approval {
  instructions = "Read an approval item you created (the item number from a 'waiting for approval' message). Returns status (waiting | approved | edited | rejected | expired | executed | failed) and, when approved or edited, approved_payload: call the same tool again with approval_id set to this item number and EXACTLY approved_payload as its input. If rejected or expired, do not retry; tell the owner."

  input {
    int approval_id filters=min:1

    text ticket? filters=trim {
      description = "COP-1 run ticket from your context. If you were given one, pass it on every tool call exactly as given. Otherwise leave it empty."
    }
  }

  stack {
    function.run "journey/tool_gate" {
      input = {journey_map_id: 0, ticket: $input.ticket, tool: "get_approval", kind: "read"}
    } as $cop1_gate

    db.query copilot_action {
      where = $db.copilot_action.id == $input.approval_id
      return = {type: "single"}
      output = ["id", "account_id", "journey_architecture_id", "status", "tool", "journey_map_id", "action_type", "summary", "approved_payload", "reason"]
    } as $act

    var $act_account {
      value = $act|get:"account_id":0
    }

    // COP-3 review fix: in a one-business conversation, only that business's approvals.
    // COP-11 (2026-11-19): except a skill change, which is filed under the account's copilot home
    // (COP-9 story 06) whichever business the chat is about - without this it could never be finished.
    db.query copilot_home {
      where = $db.copilot_home.account_id == $cop1_gate.account_id && $cop1_gate.account_id != 0
      return = {type: "single"}
      output = ["id", "journey_architecture_id"]
    } as $home

    var $home_arch {
      value = ($home|get:"journey_architecture_id":0) ?? 0
    }

    var $pin {
      value = $cop1_gate.pin_architecture_id ?? 0
    }

    var $act_arch {
      value = ($act|get:"journey_architecture_id":0) ?? 0
    }

    var $act_type_v {
      value = ($act|get:"action_type":"") ?? ""
    }

    var $act_pin_ok {
      value = ($pin == 0 || $act_arch == $pin || ($act_type_v == "skill_write" && $home_arch != 0 && $act_arch == $home_arch))
    }

    precondition ($act_account != 0 && $act_account == $cop1_gate.account_id && $act_pin_ok) {
      error_type = "notfound"
      error = "That approval was not found for this tool. Nothing was done. (E-COP-036)"
    }

    var $status {
      value = $act|get:"status":""
    }

    var $runnable {
      value = ($status == "approved" || $status == "edited")
    }
  }

  response = {
    approval_id     : $input.approval_id
    status          : $status
    tool            : ($act|get:"tool":"")
    journey_map_id  : ($act|get:"journey_map_id":0)
    action_type     : ($act|get:"action_type":"")
    summary         : ($act|get:"summary":"")
    reason          : ($act|get:"reason":"")
    approved_payload: (($runnable == true) ? ($act|get:"approved_payload":null) : null)
  }
}
