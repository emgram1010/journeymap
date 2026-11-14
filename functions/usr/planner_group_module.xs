// USR-2 (US-USR-2-04, 2026-11-14) — which module does this planner-group request need?
//
// The Planner and the performer app share ONE API group, so a group-level gate
// cannot tell them apart by itself. This function is the classification, in
// one place, so it can be tested without a token and read by a non-engineer:
//
//   EXECUTION only     perform/*                       (any verb)
//                      work_task/{id}/event            POST
//   EITHER grant       work_item/{id}                  GET   (read a job)
//                      work-item/{id}/lines            GET   (read its lines)
//                      work_item/{id}/links            GET   (parent / child jobs)
//                      work-task/{id}/exception        POST  (send work to an exception)
//   PLANNING           everything else — including any endpoint added later
//
// THE DEFAULT IS THE STRICT ONE. An endpoint nobody classified needs the
// Planner grant; it is never open. A missing path or verb also lands on
// planning. Add a line here when the performer app starts using another
// endpoint.
//
// AN ODD-LOOKING PATH IS ALSO PLANNING. Anything containing "..", "%" or a
// doubled "/" is never given the looser treatment: if the router and this
// function ever read such a path differently, "perform/../workspace" must not
// buy an execution-only person a planning endpoint.
//
// Why the lists are short: checked 2026-11-14 against every request the
// performer screens make (`src/perform/*`, `JobPeekSheet`, `ExceptionSendPanel`).
//
// HOW THE PATH IS MATCHED. A `/` inside a regex here cannot be written
// reliably: `[\/]` made every pattern return null (found by the test table on
// 2026-11-14 — it failed to the strict side, which is the only reason it was
// harmless). So the query string is cut off first, every `/` is turned into a
// space, and the patterns match on spaces: "/api:X/perform/today" becomes
// " api:X perform today".
//
// No `|` inside a string literal either (it breaks the parser, CLAUDE.md), so
// there is no regex alternation — one pattern per test, combined with `||`.
function "usr/planner_group_module" {
  input {
    // The request path as the server sees it, e.g. "/api:PE5iDldw/perform/today?tz=..."
    text uri? filters=trim

    // GET, POST, PUT, PATCH, DELETE
    text method? filters=trim
  }

  stack {
    var $no_query {
      value = "/[?].*$/"|regex_replace:"":$input.uri
    }

    var $path {
      value = $no_query|replace:"/":" "
    }

    var $m {
      value = $input.method|upper
    }

    var $has_dots {
      value = "/[.][.]/"|regex_matches:$path
    }

    var $has_percent {
      value = "/%/"|regex_matches:$path
    }

    var $has_double {
      value = "/  /"|regex_matches:$path
    }

    var $odd {
      value = ($has_dots == true) || ($has_percent == true) || ($has_double == true)
    }

    var $is_perform {
      value = "/^ api:[^ ]+ perform /"|regex_matches:$path
    }

    var $is_event {
      value = "/^ api:[^ ]+ work_task [0-9]+ event$/"|regex_matches:$path
    }

    var $is_job {
      value = "/^ api:[^ ]+ work_item [0-9]+$/"|regex_matches:$path
    }

    var $is_lines {
      value = "/^ api:[^ ]+ work-item [0-9]+ lines$/"|regex_matches:$path
    }

    var $is_links {
      value = "/^ api:[^ ]+ work_item [0-9]+ links$/"|regex_matches:$path
    }

    var $is_exception {
      value = "/^ api:[^ ]+ work-task [0-9]+ exception$/"|regex_matches:$path
    }

    var $execution_only {
      value = ($odd == false) && (($is_perform == true) || ($is_event == true && $m == "POST"))
    }

    var $either {
      value = ($odd == false) && (($is_job == true && $m == "GET") || ($is_lines == true && $m == "GET") || ($is_links == true && $m == "GET") || ($is_exception == true && $m == "POST"))
    }

    var $module {
      value = "planning"
    }

    var $or_module {
      value = ""
    }

    conditional {
      if ($execution_only == true) {
        var.update $module {
          value = "execution"
        }
      }
    }

    conditional {
      if ($execution_only == false && $either == true) {
        var.update $or_module {
          value = "execution"
        }
      }
    }
  }

  response = {module: $module, or_module: $or_module, path: $path}
}
