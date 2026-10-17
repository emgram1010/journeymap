// PLN-4, in PLN-2's guard family — Model tenancy guard.
//
// `planner_model` hangs straight off `account`, so unlike the agent and
// timeline guards this needs no workspace hop. Same contract as the
// rest: a model in another account returns exactly what a nonexistent
// one returns, so the endpoint can never be used to probe ids.
function "planner/assert_model" {
  input {
    int account_id filters=min:1
    int model_id filters=min:1
  }

  stack {
    db.get planner_model {
      field_name = "id"
      field_value = $input.model_id
    } as $model

    var $belongs {
      value = ($model != null && $model.account_id == $input.account_id)
    }

    precondition ($belongs) {
      error_type = "notfound"
      error = "Model not found"
    }
  }

  response = {model: $model}
}
