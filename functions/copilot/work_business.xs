// COP-14 story 03 — which business a planner tool works in. The ONE place this rule lives.
//   - In a copilot chat or scheduled run, the run ticket pins one business: that one, always.
//   - From the OUTSIDE MCP door only (context "outside", a person signed in with their own token,
//     via "token"), there is no pin, so the person names the business (journey_architecture_id). It must
//     be in the caller's own account - checked here again, so the rule does not depend on the gate's
//     enforce/report switch.
//   - Anything else = 0, and the tool refuses with E-COP-045. In particular an in-app call with an empty
//     ticket (which tool_caller resolves from the request's own token, context "inapp") gets NOTHING here:
//     review 2026-11-19 found that otherwise the copilot could plan as the person in any business.
// An AI identity never gets here unpinned: the gate refuses it first (E-COP-048). Only decides; never writes.
function "copilot/work_business" {
  input {
    int pin?
    text via? filters=trim
    text context? filters=trim
    int named?
    int account_id?
  }

  stack {
    db.query journey_architecture {
      where = $db.journey_architecture.id == $input.named && $input.named != 0
      return = {type: "single"}
      output = ["id", "account_id"]
    } as $named_row

    var $named_account {
      value = ($named_row|get:"account_id":0) ?? 0
    }

    var $business {
      value = 0
    }

    conditional {
      if ($input.pin != 0) {
        var.update $business {
          value = $input.pin
        }
      }

      elseif ($input.via == "token" && $input.context == "outside" && $input.named != 0 && $input.account_id != 0 && $named_account == $input.account_id) {
        var.update $business {
          value = $input.named
        }
      }
    }
  }

  response = {business: $business}
}
