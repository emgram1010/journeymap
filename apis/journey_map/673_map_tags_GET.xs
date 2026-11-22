// TAG-1 — the Tags data for the app: the account's tags with how many of the caller's visible maps carry each, and the (map, tag) links for those maps. A side table is invisible to the plain map list, so it needs its own GET (CLAUDE.md). Scoped by journey/visible_map_ids; another account's tags never appear.
query map_tags verb=GET {
  api_group = "journey-map"
  auth = "user"

  input {
  }

  stack {
    function.run "planner/resolve_actor" {
      input = {user_id: $auth.id}
    } as $actor

    function.run "journey/visible_map_ids" {
      input = {caller_account_id: $actor.account_id}
    } as $scope

    function.run "tags/overview" {
      input = {account_id: $actor.account_id, map_ids: $scope.map_ids}
    } as $o

    var $links {
      value = []
    }

    foreach ($o.links) {
      each as $l {
        array.push $links {
          value = {journey_map_id: $l.journey_map_id, map_tag_id: $l.map_tag_id}
        }
      }
    }
  }

  response = {tags: $o.tags, links: $links}
}
