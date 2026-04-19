# Financial Intelligence Lens Epic

## Goal
Add a "Financial Intelligence" actor template (actor type: `financial`) to the journey map system with 10 structured cell fields covering cost efficiency and revenue opportunity at each stage — from cost-to-serve and automation savings through revenue leakage, upsell opportunity, and financial priority scoring.

---

## Field Definitions

| # | Field Key | Label | Definition |
|---|---|---|---|
| 1 | cost_to_serve | Cost to Serve | Estimated cost per interaction, transaction, or touchpoint at this stage (e.g. "$4.20 per checkout attempt") |
| 2 | revenue_at_risk | Revenue at Risk | Revenue lost or threatened if this stage has friction or fails (e.g. "$18,400/mo in cart abandonment") |
| 3 | automation_savings | Automation Savings | Cost savings achievable if manual steps at this stage are automated (e.g. "$3.10 saved per interaction with address auto-fill") |
| 4 | upsell_opportunity | Upsell / Cross-sell Opportunity | Revenue opportunity from upsell or cross-sell actions available at this stage (e.g. "$6.50 avg order uplift if warranty shown here") |
| 5 | revenue_leakage | Revenue Leakage | Value lost due to drop-off, abandonment, errors, or rework at this stage (e.g. "18% drop-off = $47K MRR lost monthly") |
| 6 | cost_efficiency_note | Cost Efficiency Note | Key observation about cost drivers, waste, or inefficiency at this stage (e.g. "68% of support contacts here are about shipping cost — FAQ would deflect most") |
| 7 | breakeven_threshold | Breakeven Threshold | Minimum improvement required to justify the cost of fixing this stage (e.g. "Fix must recover >$500/mo to cover sprint cost") |
| 8 | cac_contribution | CAC Contribution | How this stage contributes to or inflates customer acquisition cost (e.g. "Retargeting spend at this step = $2.10 of $8.40 CAC") |
| 9 | clv_impact | CLV Impact | How this stage positively or negatively affects long-term customer lifetime value (e.g. "Slow refund at this step drives 12% churn within 90 days") |
| 10 | priority_score | Financial Priority Score | Relative investment priority based on combined cost and revenue impact (e.g. "High — $7K/mo recoverable; 2-sprint fix") |

---

## Stories

### US-FIN-01 — Add `financial` to `types.ts`
**File:** `webapp/protype-2/src/types.ts`
- Add `'financial'` to the `ActorType` union (alongside `'vendor'`, `'ai_agent'`, etc.)
- Add `FinancialActorFields` interface with all 10 keys (all `string | null | undefined`):
  `cost_to_serve`, `revenue_at_risk`, `automation_savings`, `upsell_opportunity`,
  `revenue_leakage`, `cost_efficiency_note`, `breakeven_threshold`, `cac_contribution`,
  `clv_impact`, `priority_score`
- Add `FinancialActorFields` to the `ActorFields` union type

---

### US-FIN-02 — Add financial template to `constants.ts`
**File:** `webapp/protype-2/src/constants.ts`
- Add `financial-v1` `ActorTemplate` entry with:
  - 10 `CellFieldDef` entries — labels and contextual placeholders matching field definitions above
  - `rolePrompt` describing all 10 fields for AI targeting (see Role Prompt below)
  - `cellFieldScaffold` with all 10 keys set to `null`
- Insert after the `vendor` entry to maintain ordering

**Role Prompt:**
> "You are capturing the financial intelligence perspective at each stage of this journey. For each stage focus on: Cost to Serve (estimated cost per interaction or transaction), Revenue at Risk (revenue threatened by friction or failure at this step), Automation Savings (cost reduction achievable by automating manual steps here), Upsell / Cross-sell Opportunity (revenue available from upsell or cross-sell actions at this step), Revenue Leakage (value lost to drop-off, abandonment, or rework), Cost Efficiency Note (key observation about waste or inefficiency at this step), Breakeven Threshold (minimum improvement needed to justify fixing this step), CAC Contribution (how this step affects customer acquisition cost), CLV Impact (how this step affects long-term customer lifetime value), and Financial Priority Score (relative investment priority based on combined cost and revenue impact). Be specific. Use dollar figures, percentages, and time horizons where possible. Reference upstream friction from other lenses as the root cause of financial impact."

---

### US-FIN-03 — Update add-lens API enum + scaffold
**File:** `apis/journey_map/49_journey_lens_add_journey_map_id_POST.xs`
- Add `"financial"` to the `actor_type` enum in the input validation block
- Add conditional scaffold block for `financial` type with all 10 keys set to `null`:
  `cost_to_serve`, `revenue_at_risk`, `automation_savings`, `upsell_opportunity`,
  `revenue_leakage`, `cost_efficiency_note`, `breakeven_threshold`, `cac_contribution`,
  `clv_impact`, `priority_score`
- Set `effective_template_key` to `"financial-v1"` when not provided
- Set `effective_role_prompt` to the role prompt above when not provided
- Insert the conditional block after the `vendor` block (before `db.add journey_lens`)
- Update version comment to v7

---

### US-FIN-04 — Inject financial fields into AI context
**File:** `apis/journey_map/52_journey_map_journey_map_id_ai_message_POST.xs`
- Add financial field injection block using the two-conditional pattern (filled check + null check)
  used by all existing actor types — one `if ($fv_temp != null && $fv_temp != "")` block for
  `$filled_lines` and one `if ($fv_temp == null)` block for `$empty_lines` per field
- Cover all 10 fields in order:
  1. `cost_to_serve` → label `"Cost to Serve"`
  2. `revenue_at_risk` → label `"Revenue at Risk"`
  3. `automation_savings` → label `"Automation Savings"`
  4. `upsell_opportunity` → label `"Upsell / Cross-sell Opportunity"`
  5. `revenue_leakage` → label `"Revenue Leakage"`
  6. `cost_efficiency_note` → label `"Cost Efficiency Note"`
  7. `breakeven_threshold` → label `"Breakeven Threshold"`
  8. `cac_contribution` → label `"CAC Contribution"`
  9. `clv_impact` → label `"CLV Impact"`
  10. `priority_score` → label `"Financial Priority Score"`
- Insert block after the `vendor` field injection block, before the `// Assemble the section` comment

---

### US-FIN-05 — Table schema update (Xano)
**Action:** Add `"financial"` to the `actor_type` enum on the `journey_lens` table in Xano, then pull to sync `tables/8_journey_lens.xs`.

---

### US-FIN-06 — Update scaffold structure tool
**File:** `tools/7_scaffold_structure.xs` (if this tool generates actor_fields scaffolds per type)
- Add the `financial` actor type case with all 10 null-keyed fields, matching the pattern used by other types in that file.

---

### US-FIN-07 — Update AI agent instructions
**File:** `agents/2_journey_map_assistant.xs` (or equivalent system prompt file)
- Add `financial` to any actor type enumeration in the system prompt
- Add a brief description of the financial lens purpose so the AI understands it as the "cost and revenue intelligence row" of the map, distinct from operational or customer lenses
