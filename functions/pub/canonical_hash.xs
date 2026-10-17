// PUB-1 (US-PUB-1-03/04) — Canonical serialisation + content hash for a
// version snapshot. The backend half of webapp/protype-2/src/versionHash.ts;
// the two MUST produce byte-identical strings, and the golden test in
// versionHash.test.ts pins the exact bytes both sides have to reproduce.
//
// WHY NOT json_encode: key order, whitespace and unicode escaping differ
// between encoders, so hashing encoded JSON would silently diverge from
// the frontend. The string is built field by field, in a fixed order, by
// plain concatenation instead.
//
// The escape chain (backslash first, then pipe, then CR, then LF) is
// repeated inline rather than factored into a helper function on purpose:
// a helper would mean one function.run per field — hundreds of calls for
// a real map.
//
// This is a pure function of the snapshot it is given, INCLUDING its
// array order. That is what makes verify_version meaningful: re-running
// it over a stored snapshot must reproduce the stored hash.
function "pub/canonical_hash" {
  description = "Canonical string + sha256 for a version snapshot. Pure; must match versionHash.ts byte for byte."

  input {
    json snapshot {
      description = "{schema_version, title, stages[], lenses[], cells[], links[]}"
    }
  }

  stack {
    var $schema_version {
      value = $input.snapshot.schema_version ?? 1
    }

    var $title {
      value = ($input.snapshot.title ?? "")|replace:"\\":"\\\\"|replace:"|":"\\p"|replace:"\r":""|replace:"\n":"\\n"
    }

    var $out {
      value = "v" ~ ($schema_version|to_text) ~ "\n" ~ "title|" ~ $title ~ "\n"
    }

    var $stages {
      value = $input.snapshot.stages ?? []
    }

    foreach ($stages) {
      each as $stage {
        var $s_key {
          value = ($stage.key ?? "")|replace:"\\":"\\\\"|replace:"|":"\\p"|replace:"\r":""|replace:"\n":"\\n"
        }

        var $s_label {
          value = ($stage.label ?? "")|replace:"\\":"\\\\"|replace:"|":"\\p"|replace:"\r":""|replace:"\n":"\\n"
        }

        var $s_owner {
          value = ($stage.owner_lens_key ?? "")|replace:"\\":"\\\\"|replace:"|":"\\p"|replace:"\r":""|replace:"\n":"\\n"
        }

        var.update $out {
          value = $out ~ "stage|" ~ $s_key ~ "|" ~ $s_label ~ "|" ~ $s_owner ~ "\n"
        }
      }
    }

    var $lenses {
      value = $input.snapshot.lenses ?? []
    }

    foreach ($lenses) {
      each as $lens {
        var $l_key {
          value = ($lens.key ?? "")|replace:"\\":"\\\\"|replace:"|":"\\p"|replace:"\r":""|replace:"\n":"\\n"
        }

        var $l_label {
          value = ($lens.label ?? "")|replace:"\\":"\\\\"|replace:"|":"\\p"|replace:"\r":""|replace:"\n":"\\n"
        }

        var $l_actor {
          value = ($lens.actor_type ?? "")|replace:"\\":"\\\\"|replace:"|":"\\p"|replace:"\r":""|replace:"\n":"\\n"
        }

        var $l_work {
          value = "0"
        }

        conditional {
          if ($lens.does_planned_work == true) {
            var.update $l_work {
              value = "1"
            }
          }
        }

        var.update $out {
          value = $out ~ "lens|" ~ $l_key ~ "|" ~ $l_label ~ "|" ~ $l_actor ~ "|" ~ $l_work ~ "\n"
        }
      }
    }

    var $cells {
      value = $input.snapshot.cells ?? []
    }

    foreach ($cells) {
      each as $cell {
        var $c_stage {
          value = ($cell.stage_key ?? "")|replace:"\\":"\\\\"|replace:"|":"\\p"|replace:"\r":""|replace:"\n":"\\n"
        }

        var $c_lens {
          value = ($cell.lens_key ?? "")|replace:"\\":"\\\\"|replace:"|":"\\p"|replace:"\r":""|replace:"\n":"\\n"
        }

        var $c_task {
          value = ($cell.task ?? "")|replace:"\\":"\\\\"|replace:"|":"\\p"|replace:"\r":""|replace:"\n":"\\n"
        }

        var $c_done {
          value = ($cell.done_when ?? "")|replace:"\\":"\\\\"|replace:"|":"\\p"|replace:"\r":""|replace:"\n":"\\n"
        }

        var $c_minutes {
          value = ""
        }

        conditional {
          if ($cell.duration_minutes != null) {
            var.update $c_minutes {
              value = $cell.duration_minutes|to_text
            }
          }
        }

        var.update $out {
          value = $out ~ "cell|" ~ $c_stage ~ "|" ~ $c_lens ~ "|" ~ $c_task ~ "|" ~ $c_done ~ "|" ~ $c_minutes ~ "\n"
        }
      }
    }

    var $links {
      value = $input.snapshot.links ?? []
    }

    foreach ($links) {
      each as $link {
        var $k_stage {
          value = ($link.stage_key ?? "")|replace:"\\":"\\\\"|replace:"|":"\\p"|replace:"\r":""|replace:"\n":"\\n"
        }

        var $k_lens {
          value = ($link.lens_key ?? "")|replace:"\\":"\\\\"|replace:"|":"\\p"|replace:"\r":""|replace:"\n":"\\n"
        }

        var $k_type {
          value = ($link.link_type ?? "")|replace:"\\":"\\\\"|replace:"|":"\\p"|replace:"\r":""|replace:"\n":"\\n"
        }

        var $k_target {
          value = ($link.target_map_id ?? 0)|to_text
        }

        var.update $out {
          value = $out ~ "link|" ~ $k_stage ~ "|" ~ $k_lens ~ "|" ~ $k_type ~ "|" ~ $k_target ~ "\n"
        }
      }
    }

    var $hash {
      value = $out|sha256
    }
  }

  response = {canonical: $out, hash: $hash}
}
