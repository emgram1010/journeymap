with open('product/ai-assistant.md', 'r', encoding='utf-8') as f:
    lines = f.readlines()

insert_block = [
    'Infer stage names from the domain context (e.g. for pizza delivery: Browse Menu \u2192\n',
    'Customize Order \u2192 Checkout \u2192 Order Confirmed \u2192 Preparation \u2192 Pickup / Dispatch \u2192\n',
    'Delivery \u2192 Handoff). Include all lens rows using the default lens set below.\n',
    '\n',
    '## Default lens set (US-AJS-02)\n',
    'Every map-level build MUST include these lenses via scaffold_structure. Do not omit any:\n',
    '\n',
    '| Lens | actor_type | Rule |\n',
    '|---|---|---|\n',
    '| Description | (omit) | Always first |\n',
    '| Customer | customer | Primary actor |\n',
    '| Internal actor rows | internal | One per internal role named or implied in the request |\n',
    '| Metrics | metrics | ALWAYS include \u2014 infer values from qualitative content |\n',
    '| Financial | financial | ALWAYS include \u2014 infer cost/revenue impact from context |\n',
    '| Top Pain Point | (omit) | Structural lens |\n',
    '| Key Variable | (omit) | Structural lens |\n',
    '| Cascade Risk | (omit) | Structural lens |\n',
    '| Systems | (omit) | Structural lens |\n',
    '\n',
    'The Metrics and Financial lenses are MANDATORY on every map-level build regardless of whether\n',
    'the user mentioned them. Always pass actor_type: "metrics" and actor_type: "financial" in the\n',
    'scaffold_structure lens_operations so they receive the correct template and actor_fields.\n',
    '\n',
    '## Structural vs actor lens classification (US-AJS-03)\n',
]

# Insert after line 522 (index 521)
new_lines = lines[:522] + insert_block + lines[522:]

with open('product/ai-assistant.md', 'w', encoding='utf-8') as f:
    f.writelines(new_lines)

print('Done. Total lines:', len(new_lines))
