// COP-5 story 04 (2026-11-15) — planned vs actual for one job, straight from the system's own report
// (variance/task_report, the same function the report screen uses). The copilot quotes these
// figures; it never computes variance itself.
// COP-7 story 04: the caller is checked FIRST (gate with no map: identity, daily cap, one audit
// row), and only then is the job looked up. Every miss - no such job, or another account's job -
// answers the same "Job not found". A job in another business of the same account is refused as
// another business. The tool does these two checks itself from what the gate returned, so there is
// one audit row per call, not two.
tool get_job_variance {
  instructions = "Planned vs actual for one job (work item id from list_business_jobs): for each task, expected, scheduled and actual minutes and the variance, exactly as the report screen shows them. Quote these figures; never recompute them."

  input {
    int work_item_id filters=min:1

    text ticket? filters=trim {
      description = "COP-1 run ticket from your context. If you were given one, pass it on every tool call exactly as given. Otherwise leave it empty."
    }
  }

  stack {
    function.run "journey/tool_gate" {
      input = {journey_map_id: 0, ticket: $input.ticket, tool: "get_job_variance", kind: "read"}
    } as $cop1_gate

    var $caller_account {
      value = $cop1_gate.account_id ?? 0
    }

    var $pin {
      value = $cop1_gate.pin_architecture_id ?? 0
    }

    db.query work_item {
      where = $db.work_item.id == $input.work_item_id
      return = {type: "single"}
      output = ["id", "account_id", "journey_map_version_id"]
    } as $job

    var $job_account {
      value = ($job|get:"account_id":0) ?? 0
    }

    var $version_id {
      value = ($job|get:"journey_map_version_id":0) ?? 0
    }

    db.query journey_map_version {
      where = $db.journey_map_version.id == $version_id && $version_id != 0
      return = {type: "single"}
      output = ["id", "journey_map_id"]
    } as $version

    var $map_id {
      value = ($version|get:"journey_map_id":0) ?? 0
    }

    db.query journey_map {
      where = $db.journey_map.id == $map_id && $map_id != 0
      return = {type: "single"}
      output = ["id", "account_id", "journey_architecture"]
    } as $map

    var $map_account {
      value = ($map|get:"account_id":0) ?? 0
    }

    var $map_arch {
      value = ($map|get:"journey_architecture":0) ?? 0
    }

    // One answer for every miss. Account 0 owns nothing.
    precondition ($map_id != 0 && $caller_account != 0 && $job_account == $caller_account && $map_account == $caller_account) {
      error_type = "notfound"
      error = "Job not found"
    }

    // One business at a time: the job's map must be in the conversation's business.
    precondition ($pin == 0 || $map_arch == $pin) {
      error_type = "accessdenied"
      error = "That belongs to another business. This conversation works on one business only; switch business to work on it. (E-COP-038)"
    }

    function.run "variance/task_report" {
      input = {work_item_id: $input.work_item_id}
    } as $report
  }

  response = $report
}
