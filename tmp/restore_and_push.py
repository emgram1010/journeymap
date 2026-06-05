import re

# Read the current 45-line xs file (server state)
with open('agents/2_journey_map_assistant.xs', 'r', encoding='utf-8') as f:
    xs = f.read()

print('XS lines before:', len(xs.splitlines()))
print('Current system_prompt snippet:', repr(xs[xs.find('system_prompt'):xs.find('system_prompt')+60]))

# Read the clean system prompt from ai-assistant.md
with open('product/ai-assistant.md', 'r', encoding='utf-8') as f:
    md = f.read()

# The md file IS the prompt content directly - strip any markdown frontmatter if present
# Check for conflict markers
conflicts = md.count('<<<<<<<')
print('MD conflicts:', conflicts)
print('MD lines:', len(md.splitlines()))
print('MD first 80:', repr(md[:80]))

# Build the indented prompt for the xs triple-quote block
# Each line should be indented 6 spaces
prompt_lines = md.rstrip()
indented = '\n'.join('      ' + l if l.strip() else '' for l in prompt_lines.splitlines())

# Replace the system_prompt block in the xs file
new_xs = re.sub(
    r'(system_prompt:\s*""")\s*\n\s*temp\s*\n\s*(""")',
    lambda m: m.group(1) + '\n' + indented + '\n      ' + m.group(2),
    xs,
    flags=re.DOTALL
)

if new_xs == xs:
    print('ERROR: regex did not match - no replacement made')
else:
    print('XS lines after:', len(new_xs.splitlines()))
    # Verify clean
    conflicts_after = new_xs.count('<<<<<<<')
    print('Conflicts after:', conflicts_after)
    placeholder = new_xs.count('"..."')
    print('Placeholders after:', placeholder)
    
    if conflicts_after == 0 and placeholder == 0:
        with open('agents/2_journey_map_assistant.xs', 'w', encoding='utf-8') as f:
            f.write(new_xs)
        print('Written! Ready to push.')
    else:
        print('ABORTED: clean check failed')
