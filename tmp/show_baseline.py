import json, base64

with open('.xano/branches/v1/objects.json', 'r', encoding='utf-8') as f:
    data = json.load(f)

for item in data:
    path = item.get('path', '')
    if path == 'agents/2_journey_map_assistant.xs':
        orig_b64 = item.get('original', '')
        decoded = base64.b64decode(orig_b64).decode('utf-8')
        print('=== BASELINE (objects.json original) ===')
        print(decoded)
        break
