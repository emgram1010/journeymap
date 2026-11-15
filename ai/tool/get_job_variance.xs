// COP-5 story 04 (2026-11-15) — planned vs actual for one job, straight from the system's own report
// (variance/task_report, the same function the report screen uses). The copilot quotes these
// figures; it never computes variance itself. The job's map must be in the conversation's business
// (the gate checks the map the job was made from).
tool get_job_variance {
  instructions = "Planned vs actual for one job (work item id from list_business_jobs): for each task, expected, scheduled and actual minutes and the variance, exactly as the report screen shows them. Quote these figures; never recompute them."

  input {
    int work_item_id filters=min:1

    text ticket? filters=trim {
      description = "COP-1 run ticket from your context. If you were given one, pass it on every tool call exactly as given. Otherwise leave it empty."
    }
  }

  stack {
    db.query work_item {
      where = $db.work_item.id == $input.work_item_id
      return = {type: "single"}
      output = ["id", "account_id", "journey_map_version_id"]
    } as $job

    var $version_id {
      value = $job|get:"journey_map_version_id":0
    }

    db.query journey_map_version {
      where = $db.journey_map_version.id == $version_id && $version_id != 0
      return = {type: "single"}
      output = ["id", "journey_map_id"]
    } as $version

    var $map_id {
      value = $version|get:"journey_map_id":0
    }

    precondition ($map_id != 0) {
      error_type = "notfound"
      error = "Job not found"
    }

    // The gate checks the job's map: same account, and inside the conversation's business.
    function.run "journey/tool_gate" {
      input = {journey_map_id: $map_id, ticket: $input.ticket, tool: "get_job_variance", kind: "read"}
    } as $cop1_gate

    precondition (($job|get:"account_id":0) == $cop1_gate.account_id) {
      error_type = "notfound"
      error = "Job not found"
    }

    function.run "variance/task_report" {
      input = {work_item_id: $input.work_item_id}
    } as $report
  }

  response = $report
}
