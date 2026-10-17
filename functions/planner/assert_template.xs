// PLAN-1, in PLN-2's guard family — Template tenancy guard.
//
// `plan_template` hangs straight off `account`, so like
// planner/assert_model this needs no workspace hop. Same contract as
// the rest: a template in another account returns exactly what a
// nonexistent one returns, so ids cannot be probed.
//
// Archived templates ARE returned. Archiving hides a template from
// the picker and stops new instances being made from it; it does not
// make it unreadable, because existing plans still point at it and
// their setup history should stay legible.
function "planner/assert_template" {
  input {
    int account_id filters=min:1
    int template_id filters=min:1
  }

  stack {
    db.get plan_template {
      field_name = "id"
      field_value = $input.template_id
    } as $template

    var $belongs {
      value = ($template != null && $template.account_id == $input.account_id)
    }

    precondition ($belongs) {
      error_type = "notfound"
      error = "Template not found"
    }
  }

  response = {template: $template}
}
