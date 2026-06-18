import JSZip from 'jszip';
import {loadJourneyMapBundle, type HydratedJourneyMapBundle, type XanoJourneyMap} from './xano';
import type {Lens, MatrixCell, Stage} from './types';

const yesNo = (v: unknown) => (v === true ? 'yes' : v === false ? 'no' : '—');
const dash = (v: unknown) => {
  if (v === null || v === undefined) return '—';
  const s = String(v).trim();
  return s === '' ? '—' : s;
};
const slug = (s: string) => s.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/(^-|-$)/g, '') || 'item';
const cellIcon = (c?: MatrixCell) => {
  if (!c) return '⬜';
  if (c.isLocked) return '🔒';
  if (c.status === 'confirmed' && c.content) return '✅';
  if (c.content && c.content.trim() !== '') return '◐';
  return '⬜';
};

const SETTINGS: Array<[keyof XanoJourneyMap, string]> = [
  ['primary_actor', 'Primary Actor'], ['journey_scope', 'Journey Scope'],
  ['start_point', 'Start Point'], ['end_point', 'End Point'], ['duration', 'Duration'],
  ['success_metrics', 'Success Metrics'], ['key_stakeholders', 'Key Stakeholders'],
  ['dependencies', 'Dependencies & Assumptions'], ['pain_points_summary', 'Pain Points Summary'],
  ['opportunities', 'Opportunities'], ['version', 'Version'],
];

function findCell(cells: MatrixCell[], stage: Stage, lens: Lens) {
  return cells.find((c) => c.stageId === stage.id && c.lensId === lens.id);
}

function renderActorFields(af: MatrixCell['actorFields']): string[] {
  if (!af || typeof af !== 'object') return [];
  const entries = Object.entries(af as Record<string, unknown>)
    .filter(([, v]) => v !== null && v !== undefined && String(v).trim() !== '');
  if (entries.length === 0) return [];
  return ['', '**Actor fields:**', ...entries.map(([k, v]) => `- \`${k}\`: ${String(v).trim()}`)];
}

function renderGrid(stages: Stage[], lenses: Lens[], cells: MatrixCell[]): string {
  if (stages.length === 0 || lenses.length === 0) return '_No matrix data._';
  const header = '| Lens \\ Stage | ' + stages.map((s) => s.key ?? s.id).join(' | ') + ' |';
  const sep = '|' + Array(stages.length + 1).fill('---').join('|') + '|';
  const rows = lenses.map((l) => {
    const cols = stages.map((s) => cellIcon(findCell(cells, s, l)));
    return `| ${l.key ?? l.id} (${dash(l.label)}) | ${cols.join(' | ')} |`;
  });
  return [header, sep, ...rows].join('\n');
}

function buildEntrypoint(m: XanoJourneyMap, stages: Stage[], lenses: Lens[], stageFiles: string[]): string {
  const lines = [
    `# Journey Map: ${m.title || 'Untitled'}`,
    '',
    '> Entrypoint for AI agents. Load this first; navigate to topic files as needed.',
    `> journey_map_id: ${m.id} · generated: ${new Date().toISOString()}`,
    '',
    '## At a Glance',
    `- **Title:** ${dash(m.title)}`,
    `- **Status:** ${dash(m.status)} · **Intent:** ${dash(m.intent)} · **Level:** ${dash(m.map_level)}`,
    `- **Stages:** ${stages.length} · **Lenses:** ${lenses.length} · **Cells:** ${stages.length * lenses.length}`,
    '',
    '## File Index',
    '| File | Contents | Load When |',
    '|---|---|---|',
    '| `00-metadata.md` | Map metadata, journey settings, smart AI config | Need context about scope/owners/version |',
    '| `01-actors.md` | Lens identities: actor_type, persona, goals, constraints | Need actor behavior / role detail |',
    '| `02-stages.md` | Stage goals + primary actor per stage | Need stage purpose / definition of done |',
    '| `03-matrix-grid.md` | Visual fill grid (✅ ◐ ⬜ 🔒) | Need quick scan of what is filled |',
    ...stageFiles.map((f, i) => `| \`${f}\` | All cells for stage ${i + 1} | Need cell-level detail for that stage |`),
    '| `INDEX.md` | Machine-readable map of keys → file paths | Programmatic navigation |',
    '',
    '## Stages',
    ...stages.map((s, i) => `${i + 1}. **${s.key ?? s.id}** — ${dash(s.label)}`),
    '',
    '## Lenses (Actors)',
    ...lenses.map((l) => `- **${l.key ?? l.id}** — ${dash(l.label)}${l.actorType ? ` _(${l.actorType})_` : ''}`),
    '',
    '## Suggested Reading Order',
    '1. This file (AGENTS.md) — orientation',
    '2. `03-matrix-grid.md` — visual coverage check',
    '3. `01-actors.md` + `02-stages.md` — semantic context',
    '4. `stages/*.md` — pull only the stages you need',
    '5. `00-metadata.md` — settings if the task touches scope/version',
    '',
  ];
  return lines.join('\n');
}

function buildMetadata(m: XanoJourneyMap): string {
  const lines = [
    '# Map Metadata',
    '',
    `- ID: ${m.id}`,
    `- Title: ${dash(m.title)}`,
    `- Status: ${dash(m.status)}`,
    `- Intent: ${dash(m.intent)}`,
    `- Map Level: ${dash(m.map_level)}`,
    `- Architecture: ${dash(m.journey_architecture)}`,
    `- Parent Map: ${dash(m.parent_map_id)}`,
    `- Cloned From: ${dash(m.cloned_from_map_id)}`,
    `- Created: ${dash(m.created_at)}`,
    `- Updated: ${dash(m.updated_at)}`,
    '',
    '## Journey Settings',
    ...SETTINGS.map(([k, label]) => `- ${label}: ${dash(m[k])}`),
  ];
  const sai = m.smart_ai_settings;
  if (sai) {
    lines.push('', '## Smart AI Behaviour',
      `- Interview Depth: ${dash(sai.interview_depth)}`,
      `- Insight Standard: ${dash(sai.insight_standard)}`,
      `- Lens Priority: ${dash(sai.lens_priority)}`,
      `- Emotional Mapping: ${yesNo(sai.emotional_mapping)}`,
      `- Business Impact Framing: ${yesNo(sai.business_impact_framing)}`,
      `- Auto-Confirm Writes: ${yesNo(sai.auto_confirm_writes)}`,
    );
  }
  return lines.join('\n') + '\n';
}

function buildActors(lenses: Lens[]): string {
  const lines = ['# Actors (Lenses)', ''];
  for (const l of lenses) {
    lines.push(`## ${dash(l.label)} (\`${l.key ?? l.id}\`)`);
    lines.push(`- actor_type: ${dash(l.actorType)}`);
    if (l.personaDescription) lines.push(`- persona: ${l.personaDescription}`);
    if (l.primaryGoal) lines.push(`- primary_goal: ${l.primaryGoal}`);
    if (l.standingConstraints) lines.push(`- constraints: ${l.standingConstraints}`);
    if (l.rolePrompt) lines.push(`- role_prompt: ${l.rolePrompt}`);
    lines.push('');
  }
  return lines.join('\n');
}

function buildStagesOverview(stages: Stage[]): string {
  const lines = ['# Stages (Columns)', ''];
  stages.forEach((s, i) => {
    lines.push(`## ${i + 1}. ${dash(s.label)} (\`${s.key ?? s.id}\`)`);
    if (s.stageGoal) lines.push(`- goal: ${s.stageGoal}`);
    if (s.primaryActorLens) lines.push(`- primary_actor_lens: ${s.primaryActorLens}`);
    lines.push('');
  });
  return lines.join('\n');
}

function buildGrid(stages: Stage[], lenses: Lens[], cells: MatrixCell[]): string {
  const filled = cells.filter((c) => c.content && c.content.trim() !== '').length;
  const confirmed = cells.filter((c) => c.status === 'confirmed').length;
  const locked = cells.filter((c) => c.isLocked).length;
  const total = stages.length * lenses.length;
  return [
    '# Cell Fill Grid',
    '',
    'Legend: ✅ confirmed · ◐ draft/filled · ⬜ empty · 🔒 locked',
    '',
    renderGrid(stages, lenses, cells),
    '',
    '## Fill Summary',
    `- Total cells: ${total}`,
    `- Filled: ${filled}`,
    `- Empty: ${Math.max(total - filled, 0)}`,
    `- Confirmed: ${confirmed}`,
    `- Locked: ${locked}`,
    '',
  ].join('\n');
}

function buildStageFile(stage: Stage, idx: number, lenses: Lens[], cells: MatrixCell[]): string {
  const lines = [
    `# Stage ${idx + 1}: ${dash(stage.label)} (\`${stage.key ?? stage.id}\`)`,
    '',
  ];
  if (stage.stageGoal) lines.push(`**Goal:** ${stage.stageGoal}`, '');
  if (stage.primaryActorLens) lines.push(`**Primary actor lens:** \`${stage.primaryActorLens}\``, '');
  for (const l of lenses) {
    const c = findCell(cells, stage, l);
    lines.push(`## ${dash(l.label)} (\`${l.key ?? l.id}\`)${l.actorType ? ` — ${l.actorType}` : ''}`);
    lines.push(`- status: ${c?.status ?? 'empty'} · locked: ${yesNo(c?.isLocked)} ${cellIcon(c)}`);
    lines.push('');
    lines.push(c?.content && c.content.trim() !== '' ? c.content.trim() : '_empty_');
    lines.push(...renderActorFields(c?.actorFields));
    lines.push('');
  }
  return lines.join('\n');
}

function buildIndex(m: XanoJourneyMap, stages: Stage[], lenses: Lens[], stageFiles: string[]): string {
  const payload = {
    journey_map_id: m.id,
    title: m.title,
    status: m.status,
    intent: m.intent ?? null,
    map_level: m.map_level ?? null,
    files: {
      entrypoint: 'AGENTS.md',
      metadata: '00-metadata.md',
      actors: '01-actors.md',
      stages_overview: '02-stages.md',
      grid: '03-matrix-grid.md',
      stages: stages.map((s, i) => ({key: s.key ?? s.id, label: s.label, file: stageFiles[i]})),
    },
    lenses: lenses.map((l) => ({key: l.key ?? l.id, label: l.label, actor_type: l.actorType ?? null})),
  };
  return [
    '# Index',
    '',
    'Machine-readable navigation for agents.',
    '',
    '```json',
    JSON.stringify(payload, null, 2),
    '```',
    '',
  ].join('\n');
}

export function buildJourneyMapFiles(bundle: HydratedJourneyMapBundle): Record<string, string> {
  const {journeyMap: m, stages, lenses, cells} = bundle;
  const stageFiles = stages.map((s, i) => `stages/s${i + 1}-${slug(s.key ?? s.label ?? `stage-${i + 1}`)}.md`);
  const files: Record<string, string> = {
    'AGENTS.md': buildEntrypoint(m, stages, lenses, stageFiles),
    '00-metadata.md': buildMetadata(m),
    '01-actors.md': buildActors(lenses),
    '02-stages.md': buildStagesOverview(stages),
    '03-matrix-grid.md': buildGrid(stages, lenses, cells),
    'INDEX.md': buildIndex(m, stages, lenses, stageFiles),
  };
  stages.forEach((s, i) => {
    files[stageFiles[i]] = buildStageFile(s, i, lenses, cells);
  });
  return files;
}

export async function exportJourneyMapBundle(journeyMapId: number, fallbackTitle?: string): Promise<void> {
  const bundle = await loadJourneyMapBundle(journeyMapId);
  const files = buildJourneyMapFiles(bundle);
  const folder = slug(bundle.journeyMap.title || fallbackTitle || `journey-map-${journeyMapId}`);
  const zip = new JSZip();
  const root = zip.folder(folder)!;
  for (const [path, content] of Object.entries(files)) root.file(path, content);
  const blob = await zip.generateAsync({type: 'blob'});
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = `${folder}.zip`;
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  setTimeout(() => URL.revokeObjectURL(url), 0);
}
