// PLN-5 (US-PLN-5-01) — Add someone (or something) to a plan.
//
// 4-C (2026-11-16): the rule itself now lives ONCE, in
// planner_ops/create_agent (the copilot tool plan_add_person calls the
// same function). This endpoint only signs the caller in, asks the raw
// request body which optional fields were really sent, and hands
// everything over. The function does the checks (plan, archived, model
// tenancy, E-VAL-001/002 name, E-PLN-009 capacity, E-PLN-008 model on a
// person, E-PLN-007 duplicate name), picks the colour (first palette
// colour the plan is not using), writes the row, logs the one success
// or refusal event and raises the refusal.
//
// "Was it sent?" is read here, because a function cannot see the
// request: exclude_middleware = true, or any group middleware makes
// every |has: true. Capacity left out = 8; sent as 0 = refused.
//
// Every function input is passed explicitly: one left out would
// silently inherit this endpoint's $input of the same name.
query "workspace/{workspace_id}/agent" verb=POST {
  api_group = "planner"
  auth = "user"

  input {
    int workspace_id filters=min:1
    text name filters=trim
    enum kind {
      values = ["person", "ai"]
    }

    text color? filters=trim
    decimal daily_capacity_hours?
    int model_id?
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

    var $has_color {
      value = $raw_input|has:"color"
    }

    var $has_capacity {
      value = $raw_input|has:"daily_capacity_hours"
    }

    var $has_model {
      value = $raw_input|has:"model_id"
    }

    function.run "planner_ops/create_agent" {
      input = {
        actor                   : $actor
        workspace_id            : $input.workspace_id
        name                    : $input.name
        kind                    : $input.kind
        color                   : $input.color
        has_color               : $has_color
        daily_capacity_hours    : $input.daily_capacity_hours
        has_daily_capacity_hours: $has_capacity
        model_id                : $input.model_id
        has_model_id            : $has_model
        correlation_id          : $input.correlation_id
      }
    } as $created
  }

  response = {agent: $created.agent}
}
