// COP-5 story 05 - the copilot's scheduled runs for ONE business, newest first, last 14 days, at most 30: what each run did, held and failed (the report), with counts taken from the records. Also says whether scheduled work is switched on for this business (the approval level scheduled_work, through copilot/action_level - the one place that rule lives). Account rows with no business (the copilot was switched off) are included so "why did nothing run" has an answer. Read-only. The person must hold the Intelligent Layer (this group's middleware) and the business must be in their account (E-COP-035).
query "copilot/runs" verb=GET {
  api_group = "journey-map"
  auth = "user"

  input {
    int journey_architecture_id?
  }

  stack {
    db.get user {
      field_name = "id"
      field_value = $auth.id
      output = ["id", "account_id"]
    } as $me

    var $account_id {
      value = $me|get:"account_id":0
    }

    db.query journey_architecture {
      where = $db.journey_architecture.id == $input.journey_architecture_id
      return = {type: "single"}
      output = ["id", "account_id"]
    } as $arch

    precondition ($input.journey_architecture_id != 0 && ($arch|get:"account_id":0) == $account_id && $account_id != 0) {
      error_type = "notfound"
      error = "We couldn't find that business. (E-COP-035)"
    }

    function.run "copilot/action_level" {
      input = {journey_architecture_id: $input.journey_architecture_id, action_type: "scheduled_work", amount: 0, has_amount: false}
    } as $lvl

    var $on {
      value = ($lvl.known == true) && ($lvl.effective_level != "wait")
    }

    var $now_ms {
      value = now|to_int
    }

    var $since {
      value = $now_ms - 1209600000
    }

    db.query copilot_run {
      where = $db.copilot_run.account_id == $account_id && ($db.copilot_run.journey_architecture_id == $input.journey_architecture_id || $db.copilot_run.journey_architecture_id == 0) && $db.copilot_run.created_at >= $since
      sort = {copilot_run.id: "desc"}
      return = {type: "list"}
      output = ["id", "journey_architecture_id", "trigger", "status", "started_at", "finished_at", "work_date", "open_task_count", "held_count", "told_count", "refused_count", "report", "reason"]
    } as $rows

    var $recent {
      value = $rows|slice:0:30
    }
  }

  response = {journey_architecture_id: $input.journey_architecture_id, scheduled_work_on: $on, runs: $recent}
  tags = ["cop-5"]
}
