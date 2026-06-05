with open('agents/2_journey_map_assistant.xs', 'r', encoding='utf-8') as f:
    lines = f.readlines()

print(f'Total lines: {len(lines)}')

# Find all lines with "## Specialist Mode"
specialist_lines = [i for i, l in enumerate(lines) if '## Specialist Mode' in l]
print(f'## Specialist Mode at lines: {[l+1 for l in specialist_lines]}')

# We want to keep only the FIRST occurrence (index 0) and remove lines from
# the second occurrence to just before "## Interview probing"
if len(specialist_lines) > 1:
    # Find where duplicates start: the second ## Specialist Mode
    dup_start = specialist_lines[1]
    # Find where we should resume: ## Interview probing strategies
    resume_line = None
    for i in range(dup_start, len(lines)):
        if '## Interview probing strategies' in lines[i]:
            resume_line = i
            break
    
    print(f'Duplicates: lines {dup_start+1} to {resume_line} (0-based)')
    print(f'Resuming at line {resume_line+1}: {lines[resume_line][:60]}')
    
    if resume_line is not None:
        # Remove the duplicate block (from dup_start - 1 to resume_line - 1)
        # We also remove the trailing blank line before dup_start
        remove_from = dup_start - 1  # the blank line before second ## Specialist Mode
        # But make sure we don't go before the last good line
        if lines[remove_from].strip() == '':
            pass  # yes, it's a blank line, remove it too
        else:
            remove_from = dup_start  # don't remove extra line
        
        new_lines = lines[:remove_from] + lines[resume_line:]
        print(f'New total: {len(new_lines)} lines')
        
        with open('agents/2_journey_map_assistant.xs', 'w', encoding='utf-8') as f:
            f.writelines(new_lines)
        
        # Verify
        final_count = sum(1 for l in new_lines if '## Specialist Mode' in l)
        print(f'Final ## Specialist Mode count: {final_count}')
        print('Done')
    else:
        print('Could not find resume point!')
else:
    print('No duplicates found')
