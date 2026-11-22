// TAG-1 story 01 (2026-11-21) — a tag on a map. A label beside the map, never part of it: no
// version, snapshot or hash reads this table. Unique (journey_map_id, map_tag_id): adding the
// same tag twice is a no-op. account_id is copied here so every read can be scoped without a join.
table journey_map_tag {
  auth = false

  schema {
    int id
    timestamp created_at?=now {
      visibility = "private"
    }

    int account_id? {
      table = "account"
    }

    int journey_map_id? {
      table = "journey_map"
    }

    int map_tag_id? {
      table = "map_tag"
    }

    int added_by_user_id? {
      table = "user"
    }
  }

  index = [
    {type: "primary", field: [{name: "id"}]}
    {
      type : "btree|unique"
      field: [
        {name: "journey_map_id", op: "asc"}
        {name: "map_tag_id", op: "asc"}
      ]
    }
    {type: "btree", field: [{name: "map_tag_id", op: "asc"}]}
    {type: "btree", field: [{name: "account_id", op: "asc"}]}
  ]
}