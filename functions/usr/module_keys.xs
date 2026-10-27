// USR-2 (US-USR-2-01) — the one place the three module keys are written down.
//
// `module` is a text column rather than an enum so that a fourth module is a
// configuration change instead of a schema migration on a live table. That
// only holds if the allow-list is strict and lives in ONE place, which is this
// function. Nothing else in the backend may contain a literal list of module
// keys; every write validates through here and refuses with E-USR-007.
//
// Returns the list AND answers "is this one of them?" in a single call, on
// purpose: two functions would mean two copies of the list, which is the exact
// duplication this file exists to prevent. A fourth module is one edit to the
// two lines below, together.
//
// `|contains:` returns FALSE for every array whether the value is present or
// not, and neither `in_array` nor `index_of` exists (CLAUDE.md) — so
// membership is three explicit comparisons. They are on one line because a
// multi-line boolean expression fails to parse.
//
// An omitted optional text input arrives as `""`, never null, so `valid` is
// correctly false when nothing was passed to check.
function "usr/module_keys" {
  input {
    text check? filters=trim
  }

  stack {
    var $keys {
      value = ["intelligence", "planning", "execution"]
    }

    var $valid {
      value = ($input.check == "intelligence" || $input.check == "planning" || $input.check == "execution")
    }
  }

  response = {
    keys : $keys
    valid: $valid
  }
}
