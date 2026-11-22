// TAG-1 story 02 — the account's tags, each with the number of the GIVEN maps that carry it, plus each map's tag names. The one reader behind list_tags, list_maps and the Tags screen, so a count never disagrees between them. The caller passes only the maps the person may see; a tag none of them carries shows 0. Every count is seeded to 0 first (a default with a variable key is ignored).
function "tags/overview" {
  input {
    int account_id
    int[] map_ids
  }

  stack {
    var $ids {
      value = $input.map_ids
    }

    array.push $ids {
      value = -1
    }

    db.query map_tag {
      where = $db.map_tag.account_id == $input.account_id && $input.account_id != 0
      sort = {map_tag.name_key: "asc"}
      return = {type: "list"}
    } as $tags

    db.query journey_map_tag {
      where = $db.journey_map_tag.account_id == $input.account_id && $db.journey_map_tag.journey_map_id in $ids
      return = {type: "list"}
    } as $links

    var $names {
      value = {}
    }

    var $counts {
      value = {}
    }

    var $by_map {
      value = {}
    }

    var $tk {
      value = ""
    }

    var $mk {
      value = ""
    }

    var $n {
      value = 0
    }

    var $nm {
      value = ""
    }

    var $arr {
      value = []
    }

    foreach ($tags) {
      each as $t {
        var.update $tk {
          value = "t:" ~ ($t.id|to_text)
        }

        var.update $names {
          value = $names|set:$tk:$t.name
        }

        var.update $counts {
          value = $counts|set:$tk:0
        }
      }
    }

    foreach ($links) {
      each as $l {
        var.update $tk {
          value = "t:" ~ ($l.map_tag_id|to_text)
        }

        var.update $mk {
          value = "m:" ~ ($l.journey_map_id|to_text)
        }

        var.update $n {
          value = (($counts|get:$tk:null) ?? 0) + 1
        }

        var.update $counts {
          value = $counts|set:$tk:$n
        }

        var.update $nm {
          value = ($names|get:$tk:null) ?? ""
        }

        var.update $arr {
          value = ($by_map|get:$mk:null) ?? []
        }

        array.push $arr {
          value = $nm
        }

        var.update $by_map {
          value = $by_map|set:$mk:$arr
        }
      }
    }

    var $out {
      value = []
    }

    foreach ($tags) {
      each as $t2 {
        var.update $tk {
          value = "t:" ~ ($t2.id|to_text)
        }

        var.update $n {
          value = ($counts|get:$tk:null) ?? 0
        }

        array.push $out {
          value = {map_tag_id: $t2.id, name: $t2.name, map_count: $n}
        }
      }
    }
  }

  response = {tags: $out, by_map: $by_map, links: $links}
}
