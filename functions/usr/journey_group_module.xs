// USR-2 (US-USR-2-03, 2026-11-14) — which module does this journey-map-group request need?
//
// Almost everything in this API group IS the Intelligent Layer. Three
// endpoints are not, and a plain "Intelligent Layer only" lock on the group
// would have broken them for everyone without that grant:
//
//   NO MODULE (any signed-in, switched-on person)
//                      account/me                 GET, PATCH   — the Account Settings page
//   EITHER intelligence OR planning
//                      journey_map_attachable     GET          — the old door to the Planner's map picker
//   INTELLIGENCE       everything else — including any endpoint added later
//
// THE DEFAULT IS THE STRICT ONE, and an odd-looking path ("..", "%", a
// doubled "/") is never given the looser treatment — same rule and same
// reason as usr/planner_group_module.
//
// `none: true` means "no module needed"; the caller must still check the
// person is switched on.
//
// The path is matched on spaces, not slashes: a `/` inside a regex here
// returns null (found 2026-11-14). No `|` inside a string literal either.
function "usr/journey_group_module" {
  input {
    text uri? filters=trim
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

    var $is_account_me {
      value = "/^ api:[^ ]+ account me$/"|regex_matches:$path
    }

    var $is_attachable {
      value = "/^ api:[^ ]+ journey_map_attachable$/"|regex_matches:$path
    }

    var $none {
      value = ($odd == false) && ($is_account_me == true) && ($m == "GET" || $m == "PATCH")
    }

    var $either {
      value = ($odd == false) && ($is_attachable == true) && ($m == "GET")
    }

    var $or_module {
      value = ""
    }

    conditional {
      if ($either == true) {
        var.update $or_module {
          value = "planning"
        }
      }
    }
  }

  response = {module: "intelligence", or_module: $or_module, none: $none, path: $path}
}
