import re

def resolve_file(path):
    with open(path, 'r', encoding='utf-8') as f:
        lines = f.readlines()

    # Remove all conflict marker lines and deduplicate content blocks
    out = []
    i = 0
    while i < len(lines):
        line = lines[i]
        stripped = line.rstrip('\n')
        # Skip conflict markers
        if stripped.startswith('<<<<<<<') or stripped.startswith('=======') or stripped.startswith('>>>>>>>'):
            i += 1
            continue
        out.append(line)
        i += 1

    result = ''.join(out)
    return result


# Fix agents/4_journey_map_builder.xs
# The conflict repeats the Stage Contract section 3 times; after removing markers we deduplicate.
path4 = 'agents/4_journey_map_builder.xs'
with open(path4, 'r', encoding='utf-8') as f:
    content = f.read()

# Remove conflict markers line by line
lines = content.split('\n')
clean_lines = []
for l in lines:
    s = l.strip()
    if s.startswith('<<<<<<<') or s.startswith('=======') or s.startswith('>>>>>>>'):
        continue
    clean_lines.append(l)

clean = '\n'.join(clean_lines)

# Deduplicate the repeated Stage Contract block (keep first occurrence)
marker = '      ## Stage Contract awareness'
parts = clean.split(marker)
if len(parts) > 2:
    # Keep text before first occurrence + first occurrence + text after last occurrence
    # Each part after split is everything AFTER the marker
    # parts[0] = before first marker
    # parts[1] = content after first marker up to second marker
    # parts[2] = content after second marker (which we keep for the "after" part)
    # But we need to find where the duplicate block ends
    # The pattern is: marker + block_content repeats N times
    # Just keep first block, discard duplicates
    first_block_end = parts[1].find('      ## Core rules')
    if first_block_end == -1:
        first_block_end = parts[1].find('\n      ## ')
    # Rebuild: before + marker + first_block_content + rest (from last part)
    first_block = parts[1][:first_block_end] if first_block_end != -1 else parts[1]
    rest = parts[-1]
    clean = parts[0] + marker + first_block + rest

with open(path4, 'w', encoding='utf-8') as f:
    f.write(clean)
print(f'Fixed {path4}')

# Fix agents/2_journey_map_assistant.xs - same approach, remove markers only
path2 = 'agents/2_journey_map_assistant.xs'
with open(path2, 'r', encoding='utf-8') as f:
    content = f.read()

lines = content.split('\n')
clean_lines = []
for l in lines:
    s = l.strip()
    if s.startswith('<<<<<<<') or s.startswith('=======') or s.startswith('>>>>>>>'):
        continue
    clean_lines.append(l)

clean = '\n'.join(clean_lines)

# Deduplicate repeated sections
# 1. CRUD Pre-Flight Protocol (appears 3x)
marker_crud = '      ## CRUD Pre-Flight Protocol'
parts = clean.split(marker_crud)
if len(parts) > 2:
    first_block_end = parts[1].find('      ## Skip handling rule')
    if first_block_end == -1:
        first_block_end = len(parts[1])
    first_block = parts[1][:first_block_end]
    rest = parts[-1]
    clean = parts[0] + marker_crud + first_block + rest

# 2. Stage Contract (appears 4x)
marker_sc = '      ## Stage Contract'
parts = clean.split(marker_sc)
if len(parts) > 2:
    first_block_end = parts[1].find('      ## Journey settings rules')
    if first_block_end == -1:
        first_block_end = len(parts[1])
    first_block = parts[1][:first_block_end]
    rest = parts[-1]
    clean = parts[0] + marker_sc + first_block + rest

# 3. Scaffold example rename block (appears 4x)
# Find and deduplicate "Example: action=rename" lines
example_rename = '        Example: action="rename", key="s1", label="Browse Menu"'
count = clean.count(example_rename)
if count > 1:
    idx = clean.find(example_rename)
    first_end = clean.find('\n', idx) + 1
    # Remove subsequent occurrences
    rest = clean[first_end:]
    rest_clean = rest.replace(example_rename + ', stage_goal="...", primary_actor_lens="lens-2"\n', '', count - 1)
    rest_clean = rest_clean.replace(example_rename + ', stage_goal="...", primary_actor_lens="lens-2"', '', count - 1)
    clean = clean[:first_end] + rest_clean

# 4. Scaffold example add block (appears 4x)
example_add = '        Example: action="add", label="Browse Menu"'
count = clean.count(example_add)
if count > 1:
    idx = clean.find(example_add)
    first_end = clean.find('\n', idx) + 1
    rest = clean[first_end:]
    for _ in range(count - 1):
        idx2 = rest.find(example_add)
        if idx2 == -1:
            break
        end2 = rest.find('\n', idx2) + 1
        rest = rest[:idx2] + rest[end2:]
    clean = clean[:first_end] + rest

# 5. "For both cases" paragraph (appears 4x)
marker_both = '      For both cases, infer stage_goal'
count = clean.count(marker_both)
if count > 1:
    idx = clean.find(marker_both)
    # Find end of this paragraph
    next_section = clean.find('\n\n', idx + 20)
    first_end = next_section if next_section != -1 else idx + 500
    rest = clean[first_end:]
    for _ in range(count - 1):
        idx2 = rest.find(marker_both)
        if idx2 == -1:
            break
        end2 = rest.find('\n\n', idx2 + 20)
        if end2 == -1:
            end2 = idx2 + 500
        rest = rest[:idx2] + rest[end2:]
    clean = clean[:first_end] + rest

with open(path2, 'w', encoding='utf-8') as f:
    f.write(clean)
print(f'Fixed {path2}')

print('Done')
