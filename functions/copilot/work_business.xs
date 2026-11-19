// COP-14 story 03 — which business a planner tool works in. The ONE place this rule lives.
//   - In a copilot chat or scheduled run, the run ticket pins one business: that one, always.
//   - From the outside MCP door (a person signed in with their own token, via "token"), there is no
//     pin, so the person names the business (journey_architecture_id). journey/tool_gate has already
//     refused a business that is not in the caller's account (E-COP-002), so it is safe to use here.
//   - Anything else (an unpinned ticket, nothing named) = 0, and the tool refuses with E-COP-045.
// An AI identity never gets here unpinned: the gate refuses it first (E-COP-048), even if it names one.
// Only decides; never writes.
function "copilot/work_business" {
  input {
    int pin?
    text via? filters=trim
    int named?
  }

  stack {
    var $business {
      value = 0
    }

    conditional {
      if ($input.pin != 0) {
        var.update $business {
          value = $input.pin
        }
      }

      elseif ($input.via == "token" && $input.named != 0) {
        var.update $business {
          value = $input.named
        }
      }
    }
  }

  response = {business: $business}
}
