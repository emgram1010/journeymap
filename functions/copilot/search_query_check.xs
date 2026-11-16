// COP-7 story 02/03 - THE one check on a web search made during a copilot research run. A search leaves Emgram and goes to an outside search company, so a research query must stay general. Refused shapes: the run ticket (or anything shaped like one), an email address, a long number (7+ digits, or a phone-like run), and the pinned business's own name (4+ characters). Only a research ticket (source "research", minted by research_topic) is checked; every other caller passes untouched, so older agents' searches behave as before. Never throws: returns ok + reason + message; web_search does the refusing. A refusal is logged with the reason only - never the query, never the ticket. This catches obvious shapes, not every private fact.
function "copilot/search_query_check" {
  input {
    text ticket? filters=trim
    text query? filters=trim
  }

  stack {
    function.run "usr/tool_caller" {
      input = {ticket: $input.ticket}
    } as $caller

    var $is_research {
      value = ($caller.ticket_source == "research")
    }

    var $q {
      value = $input.query|lower
    }

    // The ticket itself, or anything shaped like one.
    var $ticket_needle {
      value = "::no-ticket::"
    }

    conditional {
      if ($input.ticket != "") {
        var.update $ticket_needle {
          value = $input.ticket|lower
        }
      }
    }

    var $q_no_ticket {
      value = $q|replace:$ticket_needle:""
    }

    var $has_ticket {
      value = ($q_no_ticket != $q)
    }

    var $has_uuid {
      value = "/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}/"|regex_matches:$q
    }

    // Final review R13: an address written "name (at) domain" or "name [at] domain" is an address.
    var $q_at {
      value = $q|replace:"(at)":"@"|replace:"[at]":"@"
    }

    var $q_no_at {
      value = $q_at|replace:"@":""
    }

    var $has_email {
      value = ($q_no_at != $q_at)
    }

    // R13: "1,250,000" or "1.250.000" is a long number too - separators between digits are dropped
    // before counting.
    var $q_joined {
      value = "/(?<=[0-9])[,._'](?=[0-9])/"|regex_replace:"":$q
    }

    var $has_digits {
      value = "/[0-9]{7,}/"|regex_matches:$q_joined
    }

    // R13: a phone-like run is 9 or more DIGITS with spaces, dots, dashes or brackets between them.
    // The old shape counted characters, so a year range like "2020 - 2025" (8 digits) was refused.
    var $has_phone {
      value = "/(?:[0-9][ .()-]*){9,}/"|regex_matches:$q
    }

    // The pinned business's own name.
    var $pin {
      value = $caller.ticket_architecture_id ?? 0
    }

    db.query journey_architecture {
      where = $db.journey_architecture.id == $pin
      return = {type: "single"}
      output = ["id", "title"]
    } as $arch

    var $name_raw {
      value = ($arch|get:"title":"") ?? ""
    }

    var $name {
      value = $name_raw|lower|trim
    }

    var $name_len {
      value = $name|strlen
    }

    var $name_needle {
      value = "::no-name::"
    }

    conditional {
      if ($name_len >= 4) {
        var.update $name_needle {
          value = $name
        }
      }
    }

    var $q_no_name {
      value = $q|replace:$name_needle:""
    }

    var $has_name {
      value = ($q_no_name != $q)
    }

    var $reason {
      value = ""
    }

    conditional {
      if ($has_ticket == true || $has_uuid == true) {
        var.update $reason {
          value = "ticket"
        }
      }

      elseif ($has_email == true) {
        var.update $reason {
          value = "email"
        }
      }

      elseif ($has_digits == true || $has_phone == true) {
        var.update $reason {
          value = "long_number"
        }
      }

      elseif ($has_name == true) {
        var.update $reason {
          value = "business_name"
        }
      }
    }

    var $ok {
      value = ($is_research == false || $reason == "")
    }

    conditional {
      if ($ok == false) {
        function.run "ops/log_event" {
          input = {
            feature    : "COP-7"
            step       : "research_search_refused"
            outcome    : "rejected"
            severity   : "warn"
            error_code : "E-COP-052"
            message    : "A copilot research search was refused before it was sent."
            user_id    : $caller.user_id
            account_id : $caller.account_id
            entity_type: "journey_architecture"
            entity_id  : $pin
            metadata   : {reason: $reason}
          }
        } as $_logged
      }
    }
  }

  response = {
    ok         : $ok
    is_research: $is_research
    reason     : $reason
    message    : "Search generally: no business or customer names, contact details or long numbers. Reword the search. (E-COP-052)"
  }
}
