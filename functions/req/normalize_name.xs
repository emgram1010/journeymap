// REQ-1 story 01 — THE one name rule for a requirement. Pure: no database. `name` is what is shown: trimmed, every run of spaces collapsed to one, case kept. `key` is what two names are compared by: that same tidied name in lower case. So "Forklift", " forklift " and "FORKLIFT" share the key "forklift", and the unique index on (account, name_key) makes them one requirement. Every caller uses this function; nothing else computes a key, and the table has no column filter for it (updateTableSchema silently drops column validators). The TypeScript twin is webapp/protype-2/src/requirements/requirementModel.ts (nameKey / cleanName); both are pinned to the same examples.
function "req/normalize_name" {
  input {
    text name? filters=trim
  }

  stack {
    var $spaced {
      value = "/[[:space:]]+/"|regex_replace:" ":$input.name
    }

    var $name {
      value = $spaced|trim
    }

    var $key {
      value = $name|lower
    }
  }

  response = {name: $name, key: $key}
}
