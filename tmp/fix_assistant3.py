with open('agents/2_journey_map_assistant.xs', 'r', encoding='utf-8') as f:
    lines = f.readlines()

print(f'Total lines: {len(lines)}')

# Find duplicate "### How to detect current phase" lines
detect_lines = [i for i, l in enumerate(lines) if '### How to detect current phase' in l]
print(f'"### How to detect current phase" at lines: {[l+1 for l in detect_lines]}')

phase1_lines = [i for i, l in enumerate(lines) if '### Phase 1' in l]
print(f'"### Phase 1" at lines: {[l+1 for l in phase1_lines]}')

if len(detect_lines) > 1:
    # Second occurrence starts at detect_lines[1]
    dup_start = detect_lines[1]
    # Find where to resume: ## Build Scope Detection
    resume_line = None
    for i in range(dup_start, len(lines)):
        if '## Build Scope Detection' in lines[i]:
            resume_line = i
            break
    
    print(f'Removing lines {dup_start+1} to {resume_line} (1-based), resuming at {resume_line+1}')
    
    if resume_line is not None:
        # Remove the blank line before dup_start too if present
        remove_from = dup_start - 1 if lines[dup_start-1].strip() == '' else dup_start
        new_lines = lines[:remove_from] + lines[resume_line:]
        
        with open('agents/2_journey_map_assistant.xs', 'w', encoding='utf-8') as f:
            f.writelines(new_lines)
        
        final_detect = sum(1 for l in new_lines if '### How to detect current phase' in l)
        final_phase1 = sum(1 for l in new_lines if '### Phase 1' in l)
        print(f'Final "### How to detect" count: {final_detect}')
        print(f'Final "### Phase 1" count: {final_phase1}')
        print(f'New total lines: {len(new_lines)}')
        print('Done')
    else:
        print('ERROR: could not find ## Build Scope Detection')
else:
    print('No duplicates found')
