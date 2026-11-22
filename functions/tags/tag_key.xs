// TAG-1 story 01 — THE one place a tag name is checked and turned into its key. name is what people see (trimmed); key is the lower-case form that makes "Ops", "ops" and " OPS " one tag. Never throws: returns ok plus a friendly message, so the caller decides how to refuse.
function "tags/tag_key" {
  input {
    text name?
  }

  stack {
    var $shown {
      value = ($input.name ?? "")|trim
    }

    var $key {
      value = $shown|lower
    }

    var $len {
      value = $shown|strlen
    }

    var $has_html {
      value = (($shown|contains:"<") || ($shown|contains:">"))
    }

    var $code {
      value = ""
    }

    var $message {
      value = ""
    }

    conditional {
      if ($shown == "") {
        var.update $code {
          value = "E-TAG-001"
        }

        var.update $message {
          value = "A tag needs a name of 1 to 40 characters. (E-TAG-001)"
        }
      }

      elseif ($len > 40) {
        var.update $code {
          value = "E-TAG-001"
        }

        var.update $message {
          value = "A tag needs a name of 1 to 40 characters. (E-TAG-001)"
        }
      }

      elseif ($has_html) {
        var.update $code {
          value = "E-TAG-002"
        }

        var.update $message {
          value = "A tag name cannot contain < or >. (E-TAG-002)"
        }
      }
    }
  }

  response = {ok: ($code == ""), name: $shown, key: $key, code: $code, message: $message}
}
