# Third-Party Vendor Lens Epic

## Goal
Add a "Third-Party Vendor" actor template (actor type: `vendor`) to the journey map system with 14 structured cell fields covering the full vendor relationship at each stage — from engagement trigger and contractual obligations through SLA metrics, failure scenarios, and cost impact.

---

## Field Definitions

| # | Field Key | Label | Definition |
|---|---|---|---|
| 1 | vendor_name_type | Vendor Name / Type | Who is this third party and what category do they fall under |
| 2 | role_at_step | Role at This Step | What specific function does this vendor perform at this step |
| 3 | engagement_trigger | Engagement Trigger | What event or action activates this vendor at this step |
| 4 | contractual_obligations | Contractual Obligations | Agreed upon service levels or commitments this vendor must meet |
| 5 | information_needs | Information Needs | What data must be shared with this vendor to perform their role |
| 6 | information_returned | Information They Return | Data or confirmation the vendor sends back upon completion |
| 7 | integration_method | Integration Method | How this vendor connects to your system |
| 8 | sla_performance_metrics | SLA / Performance Metrics | How this vendor's performance is measured at this step |
| 9 | failure_scenario | Failure Scenario | What happens if this vendor fails to perform at this step |
| 10 | escalation_path | Escalation Path | Who owns the relationship and resolves issues when vendor fails |
| 11 | data_privacy_compliance | Data Privacy & Compliance | Data governance rules that apply to what is shared with this vendor |
| 12 | vendor_constraints | Vendor Constraints | Limitations the vendor operates under that affect this step |
| 13 | cost_impact | Cost Impact | Financial implication of this vendor's involvement at this step |
| 14 | dependency_on_internal | Dependency on Internal Actors | What internal teams must complete before this vendor can begin |

---

## Stories

### US-3PV-01 — Add `vendor` to `types.ts`
**File:** `webapp/protype-2/src/types.ts`
- Add `'vendor'` to `ActorType` union
- Add `VendorActorFields` interface with all 14 keys (all `string | null | undefined`)
- Add `VendorActorFields` to `ActorFields` union

---

### US-3PV-02 — Add vendor template to `constants.ts`
**File:** `webapp/protype-2/src/constants.ts`
- Add `vendor-v1` `ActorTemplate` entry with:
  - 14 `CellFieldDef` entries with labels and contextual placeholders
  - `rolePrompt` describing all 14 fields for AI targeting
  - `cellFieldScaffold` with all 14 keys set to `null`
- Insert before the `operations` (coming soon) entry to maintain ordering

---

### US-3PV-03 — Update add-lens API enum + scaffold
**File:** `apis/journey_map/49_journey_lens_add_journey_map_id_POST.xs`
- Add `"vendor"` to the `actor_type` enum
- Add conditional scaffold block for `vendor` type with all 14 keys
- Update version comment to v6

---

### US-3PV-04 — Inject vendor fields into AI context
**File:** `apis/journey_map/52_journey_map_journey_map_id_ai_message_POST.xs`
- Add vendor field injection block using the two-conditional pattern (filled / null check)
- Insert before the `// Assemble the section` comment
- Cover all 14 fields

---

### US-3PV-05 — Table schema update (Xano)
**Action:** Add `"vendor"` to the `actor_type` enum on the `journey_lens` table in Xano, then pull to sync `tables/8_journey_lens.xs`.
