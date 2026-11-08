// REPUB-1 — republish to live: latest-version selection over real
// two-version data, plus the record of the HTTP-driven cases.
//
// NOT RUN AS A WORKFLOW TEST. There is no exposed tool to execute a
// workflow_test from an AI session (CLAUDE.md). Every function.run
// assertion below was driven live through `runWorkspaceFunction` on
// 2026-11-01, with results recorded in EPIC-REPUB-1's Test Results.
//
// The endpoint's own cases were driven over REAL HTTP the same day
// (magic-link login, endpoint 562), because they need auth + the
// unique index + the transaction, which a fixture-only file cannot
// exercise:
//   FT-REPUB-1-01 republish clean       → timeline 25: v2 row added (id 16),
//                                         v1 (id 5) untouched, same hash
//   FT-REPUB-1-02 sealed by activity    → timeline 19: E-LIVE-007, named
//                                         the agent ("E2E Clerk"), wrote nothing
//   FT-REPUB-1-05 two parallel sends    → timeline 41: B won v2 (id 17),
//                                         A refused E-LIVE-008, exactly 2 rows after
//   FT-REPUB-1-08 event stamps current  → task 19 resolves publication
//                                         {id: 16, item_ref: pt-53} (soft, wrote nothing)
//   FT-REPUB-1-09 cross-account         → timeline 25 as account 6: "Timeline not found"
// Still OPEN (need fixtures a session can't safely improvise):
//   FT-REPUB-1-03 sealed by a blocked/note-only event (seal logic covers it —
//                 the count is over ALL events — but not separately driven)
//   FT-REPUB-1-04 LIVE-1 blockers on a republish
//   FT-REPUB-1-06 first publish on a fresh timeline writes version 1
//   FT-REPUB-1-07 performer view after republish (serves v2 — implied by
//                 latest_publications, not driven through perform/today)
workflow_test republish_to_live {
  stack {
    // ── Latest-version selection over REAL v1+v2 rows ──────────────────
    // Timelines 25 and 41 each hold a v1 and a v2 after the live drives
    // above; timeline 17 still holds a single v1.
    function.run "live/latest_publications" {
      input = {timeline_ids: [17, 25, 41]}
    } as $latest

    expect.to_equal ($latest.publications|count) {
      value = 3
    }

    // ── A timeline with one publication returns that one ───────────────
    function.run "live/latest_publications" {
      input = {timeline_ids: [17]}
    } as $single

    expect.to_equal (($single.publications|first).version) {
      value = 1
    }

    // ── A republished timeline returns ONLY the newest version ─────────
    function.run "live/latest_publications" {
      input = {timeline_ids: [25]}
    } as $two_versions

    expect.to_equal ($two_versions.publications|count) {
      value = 1
    }
    expect.to_equal (($two_versions.publications|first).version) {
      value = 2
    }

    // ── An unknown timeline returns nothing, not an error ──────────────
    function.run "live/latest_publications" {
      input = {timeline_ids: [999999]}
    } as $none

    expect.to_equal ($none.publications|count) {
      value = 0
    }
  }
}
