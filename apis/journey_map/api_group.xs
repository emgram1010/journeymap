// (Live, this group has no description; the comment below is local-only.)
//
// USR-2 (2026-11-14): `usr_require_journey_group` is attached here. It runs
// before every endpoint in the group and refuses anyone who is switched off
// or lacks the Intelligent Layer — except `account/me` (no module needed) and
// the old `journey_map_attachable` door (Intelligent Layer or Planner). See
// functions/usr/journey_group_module.xs. Detaching it is the rollback: push
// this file without the `middleware` line.
//
// `swagger = {active: true}` is written out on purpose: pushing a group
// without it silently turns the API docs off (found 2026-11-14).
api_group "journey-map" {
  canonical = "ER4MRRWZ"
  swagger = {active: true}
  middleware = {pre: [{name: "usr_require_journey_group"}]}
}
