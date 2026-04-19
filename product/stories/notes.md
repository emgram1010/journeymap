what

## To-Do

- [ ] Revisit `duration` field type in journey settings — consider changing from `text` to `number` if filtering/sorting by journey length becomes a requirement

- [ ] **Clean-up: Actor template single source of truth** — Right now adding a new actor type requires updating 4 separate places: `constants.ts` (scaffold keys), `49_journey_lens_add_journey_map_id_POST.xs` (hardcoded conditionals), `types.ts` (TypeScript interface), and the cell detail panel renderer. The fix: upgrade `cellFieldScaffold: Record<string, null>` in `ACTOR_TEMPLATES` to `cellFields: CellFieldDef[]` (key + label + placeholder per field). Everything else — the TypeScript type, the JSON scaffold, the cell renderer — derives from that one array automatically. Backend needs a companion Xano function `get_actor_fields_scaffold(template_key)` so the xs APIs also pull from one place instead of inline conditionals. Think of it as: one master menu, everything else reads from it.
