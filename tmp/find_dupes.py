import json, base64

with open('.xano/branches/v1/objects.json', 'r', encoding='utf-8') as f:
    data = json.load(f)

print('Total items in objects.json:', len(data))

# Find ALL agent items
print('\n=== All agent items ===')
agent_items = []
for i, item in enumerate(data):
    if item.get('type') == 'agent' or (item.get('path', '').startswith('agents/') and item.get('path', '').endswith('.xs')):
        agent_items.append((i, item))
        
for idx, (i, item) in enumerate(agent_items):
    orig_b64 = item.get('original', '')
    if orig_b64:
        decoded = base64.b64decode(orig_b64).decode('utf-8')
        lines_count = len(decoded.splitlines())
    else:
        lines_count = 0
    conflicts = decoded.count('<<<<<<<') if orig_b64 else 0
    placeholder = decoded.count('"..."') if orig_b64 else 0
    print(f'[{i}] path={item.get("path")} type={item.get("type")} lines={lines_count} conflicts={conflicts} placeholder={placeholder}')

# Check for duplicate paths among all items
path_counts = {}
for item in data:
    p = item.get('path', '')
    path_counts[p] = path_counts.get(p, 0) + 1

dupes = {p: c for p, c in path_counts.items() if c > 1}
if dupes:
    print('\n=== DUPLICATE PATHS ===')
    for p, c in dupes.items():
        print(f'{p}: {c} entries')
else:
    print('\nNo duplicate paths found.')
