import json, base64, shutil

# Step 1: Back up the clean 900-line local file
with open('agents/2_journey_map_assistant.xs', 'r', encoding='utf-8') as f:
    clean_content = f.read()

with open('tmp/clean_agent2.xs', 'w', encoding='utf-8') as f:
    f.write(clean_content)

print('Backed up clean agent 2 to tmp/clean_agent2.xs (' + str(len(clean_content.splitlines())) + ' lines)')

# Step 2: Read the 45-line "temp" baseline from objects.json
with open('.xano/branches/v1/objects.json', 'r', encoding='utf-8') as f:
    data = json.load(f)

temp_content = None
for item in data:
    if item.get('path') == 'agents/2_journey_map_assistant.xs':
        orig_b64 = item.get('original', '')
        temp_content = base64.b64decode(orig_b64).decode('utf-8')
        print('Baseline content (' + str(len(temp_content.splitlines())) + ' lines):')
        print(temp_content[:200])
        break

# Step 3: Overwrite local file with baseline ("temp" version)
# This makes local == baseline, so pull will cleanly overwrite with server state
if temp_content:
    with open('agents/2_journey_map_assistant.xs', 'w', encoding='utf-8') as f:
        f.write(temp_content)
    print('\nOverwrote local agent 2 with temp baseline.')
    print('Now run: xano workspace pull')
    print('Then run: python tmp/restore_and_push.py')
