// REQ-1 story 05 — THE one rule that turns a set of frozen needs into a canonical string and its sha256, for tamper evidence. Pure: no database. `rows` is a list of {stage_key, lens_key, requirement_id, strength}. The rows are SORTED by stage key, then row key, then requirement id (the id padded to 10 digits so text order is numeric order), and joined by EXPLICIT CONCATENATION: stage_key::lens_key::requirement_id::strength; with the pieces separated by "::" and each row ended by ";". It is NEVER built through a JSON encoder (key order, whitespace and unicode escaping differ between encoders) and never uses the pipe character (it breaks the parser even inside a string). No rows gives the empty string, whose sha256 is the pinned "no needs" hash e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855; a version with no needs stores no hash row at all. The TypeScript twin is webapp/protype-2/src/requirements/requirementModel.ts (needsCanonicalString); both are pinned to the same sample in a test. Returns the canonical string too, so a test can pin it.
function "req/needs_hash" {
  input {
    json rows
  }

  stack {
    var $keyed {
      value = []
    }

    var $idt {
      value = ""
    }

    var $full {
      value = ""
    }

    var $flen {
      value = 0
    }

    var $from {
      value = 0
    }

    var $padded {
      value = ""
    }

    var $sort_key {
      value = ""
    }

    foreach ($input.rows) {
      each as $r {
        var.update $idt {
          value = $r.requirement_id|to_text
        }

        var.update $full {
          value = "0000000000" ~ $idt
        }

        var.update $flen {
          value = $full|strlen
        }

        var.update $from {
          value = $flen - 10
        }

        var.update $padded {
          value = $full|substr:$from:10
        }

        var.update $sort_key {
          value = $r.stage_key ~ " " ~ $r.lens_key ~ " " ~ $padded
        }

        array.push $keyed {
          value = {k: $sort_key, stage_key: $r.stage_key, lens_key: $r.lens_key, requirement_id: $r.requirement_id, strength: $r.strength}
        }
      }
    }

    var $sorted {
      value = $keyed|sort:"k":"text":true
    }

    var $canonical {
      value = ""
    }

    var $rid {
      value = ""
    }

    foreach ($sorted) {
      each as $s {
        var.update $rid {
          value = $s.requirement_id|to_text
        }

        var.update $canonical {
          value = $canonical ~ $s.stage_key ~ "::" ~ $s.lens_key ~ "::" ~ $rid ~ "::" ~ $s.strength ~ ";"
        }
      }
    }

    var $hash {
      value = $canonical|sha256
    }
  }

  response = {canonical: $canonical, hash: $hash, count: ($sorted|count)}
}
