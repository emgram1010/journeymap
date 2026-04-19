// Epic 2 — Phase 2 QA workflow tests
// Covers: US-AI-2.03 (description field), US-AI-2.04 (defaults in create_draft),
//         US-AI-2.05 (load_bundle exposes descriptions), US-AI-2.08 (backfill idempotency)
workflow_test epic2_lens_descriptions {
  stack {
    // ── US-AI-2.04: create_draft seeds all 10 lenses with non-null descriptions ──
    api.call "journey_map/create_draft" verb=POST {
      api_group = "journey-map"
      input = {title: "Epic 2 Description Test", status: "draft"}
    } as $draft
  
    var $journey_map_id {
      value = $draft.journey_map.id
    }
  
    // Exactly 10 default lenses must be created
    expect.to_equal ($draft.lenses|count) {
      value = 10
    }
  
    // Every lens returned by create_draft must have a non-null description
    foreach ($draft.lenses) {
      each as $lens {
        expect.to_be_true ($lens.description != null && $lens.description != "")
      }
    }
  
    // Spot-check: painpoint description matches the canonical definition
    var $painpoint_lens {
      value = null
    }
  
    foreach ($draft.lenses) {
      each as $lens {
        conditional {
          if ($lens.key == "painpoint") {
            var.update $painpoint_lens {
              value = $lens
            }
          }
        }
      }
    }
  
    expect.to_be_true ($painpoint_lens != null)
    expect.to_equal ($painpoint_lens.description) {
      value = "The #1 friction or frustration. Must be specific — include frequency or impact."
    }
  
    // ── US-AI-2.05: load_bundle returns lenses with description field populated ──
    api.call "journey_map/load_bundle/{journey_map_id}" verb=GET {
      api_group = "journey-map"
      input = {journey_map_id: $journey_map_id}
    } as $bundle
  
    expect.to_be_true (($bundle.lenses|count) > 0)
    foreach ($bundle.lenses) {
      each as $bl {
        expect.to_be_true ($bl.description != null && $bl.description != "")
      }
    }
  
    // ── US-AI-2.08: backfill endpoint — run on a map that already has descriptions ──
    // All descriptions are already set so updated count should be 0 (idempotent)
    api.call "journey_lens/backfill_descriptions" verb=POST {
      api_group = "journey-map"
    } as $backfill_1
  
    // First run on a fully-described map returns 0 updates (all already set)
    expect.to_equal ($backfill_1.updated) {
      value = 0
    }
  
    // ── US-AI-2.08: backfill actually fills null descriptions ──
    // Create a second map and null out one lens description to simulate a pre-Epic-2 map
    api.call "journey_map/create_draft" verb=POST {
      api_group = "journey-map"
      input = {title: "Backfill Target Map", status: "draft"}
    } as $draft2
  
    // Find the risk lens in the new map and null its description via PATCH
    var $risk_lens_id {
      value = null
    }
  
    foreach ($draft2.lenses) {
      each as $lens2 {
        conditional {
          if ($lens2.key == "risk") {
            var.update $risk_lens_id {
              value = $lens2.id
            }
          }
        }
      }
    }
  
    expect.to_be_true ($risk_lens_id != null)
  
    // Directly null the description to simulate a pre-Epic-2 lens
    // (the PATCH endpoint uses filter_null, so null must be written via db.patch)
    db.patch journey_lens {
      field_name = "id"
      field_value = $risk_lens_id
      data = {description: null, updated_at: "now"}
    } as $nulled_lens
  
    expect.to_equal ($nulled_lens.id) {
      value = $risk_lens_id
    }
  
    // Run backfill — should update at least 1 lens (the one we just nulled)
    api.call "journey_lens/backfill_descriptions" verb=POST {
      api_group = "journey-map"
    } as $backfill_2
  
    expect.to_be_true ($backfill_2.updated >= 1)
  
    // Run backfill again — idempotent, should return 0 additional updates
    api.call "journey_lens/backfill_descriptions" verb=POST {
      api_group = "journey-map"
    } as $backfill_3
  
    expect.to_equal ($backfill_3.updated) {
      value = 0
    }
  }
}