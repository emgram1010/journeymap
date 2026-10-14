// PUB-1 (US-PUB-1-02) — The publish gate: AUTH-1's readiness rules plus
// the one extra rule publishing adds, a real map title (D-39).
//
// Kept separate from pub/evaluate_readiness so that function stays a pure
// mirror of AUTH-1 and can be diffed against its golden fixtures. The
// title rule lives here because it is about publishing, not authoring: a
// map called "Untitled Journey Map" is fine to keep working on, and only
// becomes a problem the moment someone tries to freeze it as a version
// other work will pin to.
//
// Output shape is the gate_failures[] contract from the earlier
// publishing initiative (code, stage_key, lens_key, message).
function "pub/evaluate_gate" {
  description = "Publish gate over a map snapshot: AUTH-1 readiness blockers plus the real-title rule."

  input {
    json snapshot {
      description = "From pub/build_map_snapshot."
    }
  }

  stack {
    function.run "pub/evaluate_readiness" {
      input = {snapshot: $input.snapshot}
    } as $readiness

    var $gate_failures {
      value = $readiness.blockers
    }

    // A placeholder title is not a real name. Compared lower-cased and
    // trimmed so "  Untitled Journey Map " is caught too. An empty title
    // is already a NO_WORK_TYPE_NAME blocker from readiness, so it is not
    // repeated here.
    var $title_normalised {
      value = ($input.snapshot.title ?? "")|trim|lower
    }

    var $is_placeholder {
      value = ($title_normalised == "untitled" || $title_normalised == "untitled map" || $title_normalised == "untitled journey map" || $title_normalised == "new map" || $title_normalised == "new journey map")
    }

    conditional {
      if ($is_placeholder == true) {
        array.push $gate_failures {
          value = {
            code     : "PLACEHOLDER_TITLE"
            stage_key: null
            lens_key : null
            message  : "Give this map a real name before publishing it."
          }
        }
      }
    }

    var $failure_count {
      value = $gate_failures|count
    }

    var $ready {
      value = ($failure_count == 0 && $readiness.total > 0)
    }
  }

  response = {
    ready        : $ready
    gate_failures: $gate_failures
    warnings     : $readiness.warnings
    ready_count  : $readiness.ready_count
    total        : $readiness.total
  }
}
