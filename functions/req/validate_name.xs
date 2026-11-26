// REQ-1 story 01 — the name rules for a requirement, one place: not empty (E-REQ-001), at most 60 characters (E-REQ-008), no HTML tag (E-REQ-002). Pure: no database. Returns ok / code / message instead of throwing, so each caller can log the refusal before raising it, and the screen keeps what the person typed. The name is tidied first (req/normalize_name), so the length is of what would be stored. A lone `<` or an ampersand is not HTML: only `<` followed by a letter is. The TypeScript twin is requirementModel.ts (validateName).
function "req/validate_name" {
  input {
    text name? filters=trim
  }

  stack {
    function.run "req/normalize_name" {
      input = {name: $input.name}
    } as $n

    var $len {
      value = $n.name|strlen
    }

    var $has_html {
      value = "/<[a-zA-Z][^>]*>/"|regex_matches:$n.name
    }

    var $code {
      value = ""
    }

    var $message {
      value = ""
    }

    conditional {
      if ($has_html == true) {
        var.update $code {
          value = "E-REQ-002"
        }

        var.update $message {
          value = "A name cannot contain HTML tags. (E-REQ-002)"
        }
      }
    }

    conditional {
      if ($len > 60) {
        var.update $code {
          value = "E-REQ-008"
        }

        var.update $message {
          value = "A name can be at most 60 characters. (E-REQ-008)"
        }
      }
    }

    conditional {
      if ($len == 0) {
        var.update $code {
          value = "E-REQ-001"
        }

        var.update $message {
          value = "Give the requirement a name. (E-REQ-001)"
        }
      }
    }
  }

  response = {ok: ($code == ""), code: $code, message: $message, name: $n.name, key: $n.key}
}
