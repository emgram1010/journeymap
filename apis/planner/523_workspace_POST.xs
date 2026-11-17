//  PLN-3 (US-PLN-3-01) — Create a plan.
//
//  `account_id` and `created_by` come from the signed-in user and are
//  never read from the request body. FT-PLN-3-02 sends an `account_id`
//  deliberately; it is not even declared as an input, so it is ignored.
//
//  4-C (2026-11-16): the rule itself now lives ONCE, in
//  planner_ops/create_workspace (the copilot tool plan_create calls the
//  same function). This endpoint only signs the caller in, works out
//  which optional fields were really sent, and hands everything over.
//  The function does the checks (first failing check wins), logs the
//  one success or refusal event, and raises the refusal.
//
//  Every function input is passed explicitly: one left out would
//  silently inherit this endpoint's $input of the same name.
//  An omitted optional DATE input does not exist at all, so a date is
//  only read inside the "was it sent" branch and handed over as text.
query workspace verb=POST {
  api_group = "planner"
  auth = "user"

  input {
    text name filters=trim
    date planning_window_start?
    date planning_window_end?
    int input_tokens_per_minute?
    int output_tokens_per_minute?
    text correlation_id? filters=trim
  }

  stack {
    function.run "planner/resolve_actor" {
      input = {user_id: $auth.id}
    } as $actor

    util.get_raw_input {
      encoding = "json"
      exclude_middleware = true
    } as $raw_input

    var $has_start {
      value = $raw_input|has:"planning_window_start"
    }

    var $has_end {
      value = $raw_input|has:"planning_window_end"
    }

    var $has_input_rate {
      value = $raw_input|has:"input_tokens_per_minute"
    }

    var $has_output_rate {
      value = $raw_input|has:"output_tokens_per_minute"
    }

    var $start_text {
      value = ""
    }

    conditional {
      if ($raw_input|has:"planning_window_start") {
        var.update $start_text {
          value = $input.planning_window_start
        }
      }
    }

    var $end_text {
      value = ""
    }

    conditional {
      if ($raw_input|has:"planning_window_end") {
        var.update $end_text {
          value = $input.planning_window_end
        }
      }
    }

    function.run "planner_ops/create_workspace" {
      input = {
        actor                       : $actor
        name                        : $input.name
        planning_window_start       : $start_text
        has_planning_window_start   : $has_start
        planning_window_end         : $end_text
        has_planning_window_end     : $has_end
        input_tokens_per_minute     : $input.input_tokens_per_minute
        has_input_tokens_per_minute : $has_input_rate
        output_tokens_per_minute    : $input.output_tokens_per_minute
        has_output_tokens_per_minute: $has_output_rate
        correlation_id              : $input.correlation_id
      }
    } as $created
  }

  response = {
    workspace: $created.workspace
    counts   : $created.counts
  }
}
