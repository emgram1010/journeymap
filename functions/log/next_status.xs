// LOG-1 (US-LOG-1-02) — The transition table, in one place.
//
// THE SINGLE BACKEND COPY. The record-event endpoint and the replay
// audit both call this. They used to hold their own copies of the
// table, which is precisely the drift the epic warns about: an audit
// that disagrees with the engine it audits is worse than no audit,
// because it reports healthy data as broken (or the reverse) with
// full confidence.
//
// The pure-TypeScript twin is `logModel.ts::canTransition`, tested
// against a copy of the epic's table transcribed independently of
// either implementation. If this and that ever disagree, that test
// is the one that should win.
//
// `to` comes back as "" when the move is not allowed. A `note` is
// allowed from every status and changes nothing.
function "log/next_status" {
  input {
    text from filters=trim
    text event filters=trim
  }

  stack {
    var $to {
      value = ""
    }

    conditional {
      if ($input.event == "note") {
        var.update $to {
          value = $input.from
        }
      }
    }

    conditional {
      if ($input.from == "not_started" && $input.event == "started") {
        var.update $to {
          value = "in_progress"
        }
      }
    }

    conditional {
      if ($input.from == "not_started" && $input.event == "blocked") {
        var.update $to {
          value = "blocked"
        }
      }
    }

    conditional {
      if ($input.from == "not_started" && $input.event == "skipped") {
        var.update $to {
          value = "skipped"
        }
      }
    }

    // Done without Start (D-38). People finish things without
    // pressing Start; refusing it would push them to invent a start
    // time, which is worse than an honestly unknown one.
    conditional {
      if ($input.from == "not_started" && $input.event == "completed") {
        var.update $to {
          value = "done"
        }
      }
    }

    conditional {
      if ($input.from == "in_progress" && $input.event == "completed") {
        var.update $to {
          value = "done"
        }
      }
    }

    conditional {
      if ($input.from == "in_progress" && $input.event == "blocked") {
        var.update $to {
          value = "blocked"
        }
      }
    }

    conditional {
      if ($input.from == "in_progress" && $input.event == "skipped") {
        var.update $to {
          value = "skipped"
        }
      }
    }

    conditional {
      if ($input.from == "blocked" && $input.event == "unblocked") {
        var.update $to {
          value = "in_progress"
        }
      }
    }

    conditional {
      if ($input.from == "blocked" && $input.event == "skipped") {
        var.update $to {
          value = "skipped"
        }
      }
    }

    conditional {
      if ($input.from == "done" && $input.event == "reopened") {
        var.update $to {
          value = "in_progress"
        }
      }
    }

    conditional {
      if ($input.from == "skipped" && $input.event == "reopened") {
        var.update $to {
          value = "in_progress"
        }
      }
    }

    // The friendly sentence for a refusal. Never shows the raw enum
    // (VAL-1): "This step is in_progress" is not English.
    var $message {
      value = "That action isn't available for this step right now."
    }

    conditional {
      if ($input.from == "done") {
        var.update $message {
          value = "This step is already done. Reopen it first if you need to change it."
        }
      }
    }

    conditional {
      if ($input.from == "skipped") {
        var.update $message {
          value = "This step was skipped. Reopen it first if you need to change it."
        }
      }
    }

    conditional {
      if ($input.from == "blocked") {
        var.update $message {
          value = "This step is blocked. Unblock it first."
        }
      }
    }

    conditional {
      if ($input.from == "in_progress") {
        var.update $message {
          value = "This step is already in progress."
        }
      }
    }

    conditional {
      if ($input.from == "not_started") {
        var.update $message {
          value = "This step hasn't been started, so that action isn't available yet."
        }
      }
    }
  }

  response = {
    to     : $to
    allowed: ($to != "")
    message: $message
  }
}
