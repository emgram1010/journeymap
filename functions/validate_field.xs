// VAL-1 (US-VAL-1-02) — The backend half of the shared rule engine.
// Same behaviour as webapp/protype-2/src/validation/validate.ts, kept
// in sync by hand (no shared build step between Xano and Vite — same
// pattern as OBS-1's error catalog). Proved equal via golden fixtures
// (validate.goldenFixtures.test.ts calls this through
// runWorkspaceFunction once pushed, and checks the SAME fixture file
// the frontend test uses).
//
// Only the rule shapes actually used by phase-4 endpoints today are
// implemented: text, int, enum. Add decimal/date/time here if and when
// an endpoint needs them server-side (the frontend has all five).
//
// has_max_length / has_min_value / has_max_value exist because an
// OMITTED optional int input arrives as 0, not null (verified
// constraint, see CLAUDE.md) — `$input.max_length != null` would never
// be true, so a limit of 0 could never be told apart from "no limit".
function "validate_field" {
  description = "Validates one raw value against one rule. Never throws; returns {ok, value|code+message}."

  input {
    text raw? filters=trim
    text type filters=trim {
      description = "text | int | enum"
    }
    bool required?
    text label filters=trim
    int max_length?
    bool has_max_length?
    int min_value?
    bool has_min_value?
    int max_value?
    bool has_max_value?
    bool no_html?
    json allowed_values? {
      description = "enum only: an array of allowed strings."
    }
    text required_code? filters=trim
    text too_long_code? filters=trim
    text invalid_code? filters=trim
    text out_of_range_code? filters=trim
    text not_allowed_code? filters=trim
    text html_code? filters=trim
  }

  stack {
    var $raw_value {
      value = $input.raw ?? ""
    }

    var $trimmed {
      value = $raw_value|trim
    }

    var $ok {
      value = true
    }

    var $code {
      value = null
    }

    var $message {
      value = null
    }

    var $value {
      value = $trimmed
    }

    conditional {
      if ($trimmed == "") {
        conditional {
          if ($input.required == true) {
            var.update $ok {
              value = false
            }

            var.update $code {
              value = $input.required_code ?? "E-VAL-001"
            }

            var.update $message {
              value = $input.label ~ " is required."
            }
          }
        }
      }

      else {
        conditional {
          if ($input.type == "text") {
            conditional {
              if ($input.no_html == true && ("/<[a-zA-Z][^>]*>/"|regex_matches:$trimmed)) {
                var.update $ok {
                  value = false
                }

                var.update $code {
                  value = $input.html_code ?? "E-VAL-005"
                }

                var.update $message {
                  value = $input.label ~ " can't contain HTML."
                }
              }
            }

            var $text_len {
              value = $trimmed|strlen
            }

            conditional {
              if ($ok == true && $input.has_max_length == true && $text_len > $input.max_length) {
                var.update $ok {
                  value = false
                }

                var.update $code {
                  value = $input.too_long_code ?? "E-VAL-002"
                }

                var.update $message {
                  value = $input.label ~ " must be " ~ ($input.max_length|to_text) ~ " characters or fewer."
                }
              }
            }
          }

          elseif ($input.type == "enum") {
            var $allowed {
              value = $input.allowed_values ?? []
            }

            var $is_allowed {
              value = $allowed|in:$trimmed
            }

            conditional {
              if ($is_allowed == false) {
                var.update $ok {
                  value = false
                }

                var.update $code {
                  value = $input.not_allowed_code ?? "E-VAL-004"
                }

                var.update $message {
                  value = $input.label ~ " must be one of the allowed options."
                }
              }
            }
          }

          elseif ($input.type == "int") {
            var $parsed {
              value = $trimmed|to_int
            }

            var $round_trips {
              value = ($parsed|to_text) == $trimmed
            }

            conditional {
              if ($round_trips == false) {
                var.update $ok {
                  value = false
                }

                var.update $code {
                  value = $input.invalid_code ?? "E-VAL-003"
                }

                var.update $message {
                  value = $input.label ~ " must be a whole number."
                }
              }

              else {
                var.update $value {
                  value = $parsed|to_text
                }

                conditional {
                  if ($input.has_min_value == true && $parsed < $input.min_value) {
                    var.update $ok {
                      value = false
                    }

                    var.update $code {
                      value = $input.out_of_range_code ?? "E-VAL-003"
                    }

                    var.update $message {
                      value = $input.label ~ " must be at least " ~ ($input.min_value|to_text) ~ "."
                    }
                  }
                }

                conditional {
                  if ($ok == true && $input.has_max_value == true && $parsed > $input.max_value) {
                    var.update $ok {
                      value = false
                    }

                    var.update $code {
                      value = $input.out_of_range_code ?? "E-VAL-003"
                    }

                    var.update $message {
                      value = $input.label ~ " must be " ~ ($input.max_value|to_text) ~ " or less."
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  response = {
    ok     : $ok
    value  : $value
    code   : $code
    message: $message
  }
}
