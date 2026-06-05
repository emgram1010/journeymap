import os

agents = [
    'agents/2_journey_map_assistant.xs',
    'agents/4_journey_map_builder.xs',
    'agents/3_journey_compare_analyst.xs',
    'agents/5_journey_map_chat_agent.xs',
    'agents/15_journey_map_orchestrator.xs',
]

dotdotdot = '="..."'

for path in agents:
    if not os.path.exists(path):
        print(path + ': NOT FOUND')
        continue
    with open(path, 'r', encoding='utf-8') as f:
        c = f.read()
    conflict = c.count('<<<<<<<')
    placeholder = c.count(dotdotdot)
    print(path + ': conflict=' + str(conflict) + ' placeholder=' + str(placeholder) + ' lines=' + str(len(c.splitlines())))
    if placeholder > 0:
        lines = c.splitlines()
        for i, l in enumerate(lines):
            if dotdotdot in l:
                print('  line ' + str(i+1) + ': ' + l.strip())
