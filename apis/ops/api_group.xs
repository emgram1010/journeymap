// OBS-1 (phase-4) — Client event ingestion, the Health page's data, and
// the diagnostic bundle. Every ops/* endpoint except ops/event requires
// a platform admin (ops/require_platform_admin) — see
// product/stories/phase-4/EPIC-OBS-1-observability-and-heartbeat.md.
//
// NOTE: `canonical` is assigned by Xano the first time this group is
// created there. This file has not been pushed yet — do not invent a
// value here.
api_group "Ops" {
  tags = ["phase-4", "obs-1"]
}
