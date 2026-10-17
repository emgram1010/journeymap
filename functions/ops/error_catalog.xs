// OBS-1 (US-OBS-1-03) — Backend copy of the error catalog.
//
// The authoritative, human-edited catalog lives in
// webapp/protype-2/src/ops/errorCatalog.json (used by the frontend for
// inline field errors and the Health page). This function is a small
// backend copy of the SAME entries, used only where the backend itself
// needs catalog text at runtime (currently: build_diagnostic_bundle and
// group_issues, so a bundle/issue can show its owner and suggested fix
// without a round trip to the frontend).
//
// IMPORTANT — keep in sync by hand: whenever a new error code is added to
// the frontend catalog, add the same entry here too. There is no shared
// build step between the Xano backend and the Vite frontend in this repo,
// so this sync is manual. Only OBS-1's own codes are listed for now;
// later epics add their codes to both places as they are built.
function "ops/error_catalog" {
  description = "Returns the backend's copy of the error catalog as a map keyed by code."

  input {
  }

  stack {
    var $catalog {
      value = {}
        |set:"E-OBS-001":{
          code         : "E-OBS-001"
          feature      : "OBS-1"
          user_message : "You don't have access to this page."
          what_happened: "A non-admin user (or an unauthenticated request) tried to reach an ops/* endpoint or the Health page."
          likely_cause : "The caller's user record does not have is_platform_admin set to true."
          owner        : "engineer"
          severity     : "warn"
          fix_hint     : "If this user should be a platform admin, set user.is_platform_admin = true directly in the database. There is no UI for this on purpose."
        }
        |set:"E-OBS-002":{
          code         : "E-OBS-002"
          feature      : "OBS-1"
          user_message : "Too many reports were sent in a short time, so we slowed down."
          what_happened: "The client event endpoint's rate limit (20 per minute per user) was hit, usually from a screen stuck in an error loop."
          likely_cause : "A front-end bug is repeatedly failing and reporting the same error."
          owner        : "engineer"
          severity     : "info"
          fix_hint     : "Check the Health page's issue list for the feature/step that is flooding, and fix the underlying front-end error."
        }
    }
  }

  response = $catalog

  test "contains the OBS-1 access-denied entry" {
    expect.to_equal ($response|get:"E-OBS-001.owner":null) {
      value = "engineer"
    }
  }
}
