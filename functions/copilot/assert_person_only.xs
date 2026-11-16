// Handoff 4-A rule 1 (COP-5 story 02) - THE one check for actions only a person may take (Publish to live). An AI identity (copilot/identity_for_user) is refused with the same code and words the approval gate uses for person-only types (E-COP-025), and the refusal is logged as a rejected event. A person passes untouched. Called right after the caller is known, before anything is written.
function "copilot/assert_person_only" {
  input {
    int user_id
    int account_id?
    text step? filters=trim
    text entity_type? filters=trim
    int entity_id?
  }

  stack {
    function.run "copilot/identity_for_user" {
      input = {user_id: $input.user_id}
    } as $who

    var $is_ai {
      value = ($who.is_ai == true)
    }

    conditional {
      if ($is_ai == true) {
        function.run "ops/log_event" {
          input = {
            feature    : "COP-5"
            step       : $input.step
            outcome    : "rejected"
            severity   : "warn"
            error_code : "E-COP-025"
            message    : "An AI identity tried an action only a person may take."
            user_id    : $input.user_id
            account_id : $input.account_id
            entity_type: $input.entity_type
            entity_id  : $input.entity_id
            metadata   : {}
          }
        } as $_refused_logged
      }
    }

    precondition ($is_ai == false) {
      error_type = "accessdenied"
      error = "Only a person can do this. It is ready for the owner to do themselves. (E-COP-025)"
    }
  }

  response = {ok: true}
}
