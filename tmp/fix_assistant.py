with open('agents/2_journey_map_assistant.xs', 'r', encoding='utf-8') as f:
    content = f.read()

# The duplicate sections to deduplicate:
# 1. ## Specialist Mode + ## Consortium Mode block (appears 5 times, keep 1)
# 2. ## Stage Contract block (the deduplication may have left multiple copies)
# 3. Guided Interview Flow phases (may be duplicated)

def keep_first(text, marker, next_section=None):
    """Keep only the first occurrence of marker + its content up to next_section."""
    parts = text.split(marker)
    if len(parts) <= 2:
        return text  # 0 or 1 occurrence, nothing to do
    
    # Find where the first block ends
    if next_section:
        end_idx = parts[1].find(next_section)
        if end_idx == -1:
            # Fallback: keep everything after first occurrence
            return parts[0] + marker + parts[1]
        first_block = parts[1][:end_idx]
        rest = parts[-1]
        # The rest starts from next_section
        rest_idx = rest.find(next_section)
        if rest_idx == -1:
            rest_idx = 0
        return parts[0] + marker + first_block + rest[rest_idx:]
    else:
        # Just keep first + last remainder
        return parts[0] + marker + parts[1]

# Deduplicate Specialist Mode sections (5 occurrences → 1)
# The specialist + consortium pair appears 5 times between ## Chat mode rules and ## Interview probing
specialist_block = '      ## Specialist Mode\n      When the dynamic context contains a "## Specialist Persona" block:\n      - You ARE that actor for this entire conversation. Answer in first person using their name/role.\n      - Ground every answer in their persona_description, primary_goal, and standing_constraints.\n      - When asked about a specific stage, call get_stage_detail to read their cell data, then respond as that actor would — from their perspective, priorities, and constraints.\n      - Stay in character. Do NOT say "as an AI" or break persona.\n      - If asked "what should I do?", give the actor\'s specific recommendation, not generic advice.\n      - Tone and voice should match the actor\'s role (e.g. The Lawyer is precise and cautious, The Coach is direct and motivating).\n      - Do NOT modify cells in Specialist Mode unless the user explicitly requests an edit.\n\n      ## Consortium Mode\n      When the dynamic context contains a "## Consortium Panel" block:\n      - You represent ALL listed actors simultaneously.\n      - For each user question, provide each actor\'s perspective in this exact format:\n        **[Actor Name]:** <their take, 1–3 sentences>\n        **[Actor Name]:** <their take, 1–3 sentences>\n        **Synthesis:** <where they align or diverge, 1–2 sentences>\n      - Surface real tension between actors when it exists — do not smooth over disagreement.\n      - When the question is stage-specific, call get_stage_detail once and use it to inform all actor voices.\n      - Keep each actor voice distinct and grounded in their identity from the Consortium Panel block.\n      - Do NOT modify cells in Consortium Mode.'

# Count how many times it appears
count = content.count(specialist_block)
print(f'Specialist+Consortium block appears {count} times')

if count > 1:
    # Keep only the first occurrence
    idx = content.find(specialist_block)
    # Remove all subsequent occurrences
    while True:
        idx2 = content.find(specialist_block, idx + len(specialist_block))
        if idx2 == -1:
            break
        # Remove this occurrence plus any surrounding whitespace
        before = content[:idx2]
        after = content[idx2 + len(specialist_block):]
        # Also remove leading/trailing blank lines
        after = after.lstrip('\n')
        content = before + '\n' + after
        count -= 1
        print(f'Removed one duplicate, {count} remaining')

# Also check for the trailing whitespace variant
specialist_trailing = specialist_block + '\n      '
while specialist_trailing in content:
    idx = content.find(specialist_trailing)
    after_idx = content.find(specialist_block, idx + len(specialist_trailing))
    if after_idx == -1:
        break
    content = content[:after_idx] + content[after_idx + len(specialist_trailing):]
    print('Removed trailing-whitespace variant')

# Verify final count
final_count = content.count('## Specialist Mode')
print(f'Final Specialist Mode count: {final_count}')

with open('agents/2_journey_map_assistant.xs', 'w', encoding='utf-8') as f:
    f.write(content)

total_lines = len(content.splitlines())
print(f'Total lines: {total_lines}')
print('Done')
