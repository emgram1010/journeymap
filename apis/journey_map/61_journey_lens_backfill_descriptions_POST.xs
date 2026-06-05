// US-AI-2.08 — Populate default descriptions on existing lenses where description IS NULL
// and key matches a known default key. Custom/non-default keys are skipped.
// Idempotent: running twice has no additional effect.
query "journey_lens/backfill_descriptions" verb=POST {
  api_group = "journey-map"

  input {
  }

  stack {
    // ── Define default descriptions keyed by lens key ──
    var $defaults {
      value = {}
        |set:"description":"Brief summary of what happens at this stage — the core activity."
        |set:"customer":"Who is the end customer at this stage? What do they experience or feel?"
        |set:"owner":"The single team or role responsible for this stage succeeding."
        |set:"supporting":"Other teams/roles that contribute but don't own the outcome."
        |set:"painpoint":"The #1 friction or frustration. Must be specific — include frequency or impact."
        |set:"variable":"The single critical factor determining success or failure. Must be measurable."
        |set:"risk":"When this stage fails, which downstream stages break? Describe the domino chain."
        |set:"trigger":"The threshold or event requiring escalation. Must include a measurable condition."
        |set:"notifications":"What notifications fire, to whom, via what channel? Format: [Channel]: [Recipient] — [Content]."
        |set:"systems":"The specific technology, software, or tools involved. Be specific, not generic."
    }
  
    // ── Load all lenses that have a null description ──
    db.query journey_lens {
      where = $db.journey_lens.description == null
      return = {type: "list"}
    } as $null_desc_lenses
  
    var $updated_count {
      value = 0
    }
  
    // ── For each lens, check if its key is a known default and backfill ──
    foreach ($null_desc_lenses) {
      each as $lens {
        var $default_desc {
          value = $defaults|get:$lens.key
        }
      
        conditional {
          if ($default_desc != null) {
            db.patch journey_lens {
              field_name = "id"
              field_value = $lens.id
              data = {description: $default_desc, updated_at: "now"}
            } as $patch_result
          
            conditional {
              if ($patch_result.id != null) {
                var.update $updated_count {
                  value = $updated_count + 1
                }
              }
            }
          }
        }
      }
    }
  }

  response = {
    updated: $updated_count
    message: "Backfill complete. Custom or already-described lenses were skipped."
  }
}