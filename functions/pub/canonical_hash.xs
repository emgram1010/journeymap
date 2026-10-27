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
      description = "{schema_version, title, stages[], lenses[], cells[], links[]}, plus scaling[] and rates[] when schema_version >= 2"
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

        // Same `??` guard as duration below: a missing key must not throw.
        var $l_works_raw {
          value = $lens.does_planned_work ?? false
        }

        conditional {
          if ($l_works_raw == true) {
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

        // RATE-1: read through `??` first. A bare `$cell.duration_minutes`
        // in a condition THROWS when the key is absent ("Unable to locate
        // var"), which made version 5 (a hand-built PUB-1 fixture whose
        // cells have no duration key) unverifiable. Output is unchanged for
        // every cell that has the key; an absent key renders "" exactly as
        // versionHash.ts does for undefined.
        var $c_duration_raw {
          value = $cell.duration_minutes ?? null
        }

        conditional {
          if ($c_duration_raw != null) {
            var.update $c_minutes {
              value = $c_duration_raw|to_text
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

    // ── RATE-1 (US-RATE-1-03) — schema v2: scaling + rates ─────────────
    // Gated on the snapshot's OWN schema_version (read before any loop),
    // so a stored v1 snapshot re-serialises to exactly its old bytes.
    // Minutes are always fixed 2 decimals via number_format, which is
    // identical to JS toFixed(2) for every value with at most 2 decimals —
    // all a snapshot can hold (E-ITM-004 + build_map_snapshot's rounding).
    var $scaling {
      value = $input.snapshot.scaling ?? []
    }

    var $rates {
      value = $input.snapshot.rates ?? []
    }

    conditional {
      if ($schema_version >= 2) {
        foreach ($scaling) {
          each as $sc {
            var $sc_stage {
              value = ($sc.stage_key ?? "")|replace:"\\":"\\\\"|replace:"|":"\\p"|replace:"\r":""|replace:"\n":"\\n"
            }

            var $sc_with {
              value = ($sc.scales_with ?? "")|replace:"\\":"\\\\"|replace:"|":"\\p"|replace:"\r":""|replace:"\n":"\\n"
            }

            var.update $out {
              value = $out ~ "scale|" ~ $sc_stage ~ "|" ~ $sc_with ~ "\n"
            }
          }
        }

        foreach ($rates) {
          each as $rt {
            var $rt_stage {
              value = ($rt.stage_key ?? "")|replace:"\\":"\\\\"|replace:"|":"\\p"|replace:"\r":""|replace:"\n":"\\n"
            }

            var $rt_qty {
              value = ($rt.quantity_key ?? "")|replace:"\\":"\\\\"|replace:"|":"\\p"|replace:"\r":""|replace:"\n":"\\n"
            }

            var $rt_method {
              value = ($rt.method_key ?? "")|replace:"\\":"\\\\"|replace:"|":"\\p"|replace:"\r":""|replace:"\n":"\\n"
            }

            var $rt_minutes {
              value = ($rt.minutes_per_unit ?? 0)|number_format:2:".":""
            }

            var $rt_source {
              value = ($rt.source ?? "")|replace:"\\":"\\\\"|replace:"|":"\\p"|replace:"\r":""|replace:"\n":"\\n"
            }

            var.update $out {
              value = $out ~ "rate|" ~ $rt_stage ~ "|" ~ $rt_qty ~ "|" ~ $rt_method ~ "|" ~ $rt_minutes ~ "|" ~ $rt_source ~ "\n"
            }
          }
        }
      }
    }

    var $hash {
      value = $out|sha256
    }
  }

  response = {canonical: $out, hash: $hash}
}
