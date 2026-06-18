import {loadJourneyMapBundle, type HydratedJourneyMapBundle, type XanoJourneyMap} from './xano';
import type {Lens, MatrixCell, Stage} from './types';

const yesNo = (v: unknown) => (v === true ? 'yes' : v === false ? 'no' : 'unknown');
const dash = (v: unknown) => {
  if (v === null || v === undefined) return 'not set';
  const s = String(v).trim();
  return s === '' ? 'not set' : s;
};
const snake = (s: string) => s.toLowerCase().replace(/[^a-z0-9]+/g, '_').replace(/(^_|_$)/g, '') || 'journey_map';

const cellState = (c?: MatrixCell): string => {
  if (!c) return 'empty';
  if (c.isLocked) return 'locked';
  if (c.status === 'confirmed' && c.content) return 'confirmed';
  if (c.content && c.content.trim() !== '') return 'draft';
  return 'empty';
};

const settingsFields: Array<[keyof XanoJourneyMap, string]> = [
  ['primary_actor', 'Primary actor'],
  ['journey_scope', 'Journey scope'],
  ['start_point', 'Start point'],
  ['end_point', 'End point'],
  ['duration', 'Duration'],
  ['success_metrics', 'Success metrics'],
  ['key_stakeholders', 'Key stakeholders'],
  ['dependencies', 'Dependencies and assumptions'],
  ['pain_points_summary', 'Pain points summary'],
  ['opportunities', 'Opportunities'],
  ['version', 'Version'],
];

function renderGrid(stages: Stage[], lenses: Lens[], cells: MatrixCell[]): string {
  if (stages.length === 0 || lenses.length === 0) return 'No matrix data available.';
  const header = '| Lens \\ Stage | ' + stages.map((s) => dash(s.label)).join(' | ') + ' |';
  const sep = '|' + Array(stages.length + 1).fill('---').join('|') + '|';
  const rows = lenses.map((l) => {
    const cols = stages.map((s) => cellState(cells.find((x) => x.stageId === s.id && x.lensId === l.id)));
    return `| ${dash(l.label)} | ${cols.join(' | ')} |`;
  });
  return [header, sep, ...rows].join('\n');
}

function renderActorFields(af: MatrixCell['actorFields']): string {
  if (!af || typeof af !== 'object') return '';
  const entries = Object.entries(af as Record<string, unknown>).filter(([, v]) => v !== null && v !== undefined && String(v).trim() !== '');
  if (entries.length === 0) return '';
  return ['', 'Actor fields:', ...entries.map(([k, v]) => `- ${k}: ${String(v).trim()}`)].join('\n');
}

export function buildJourneyMapNotebookLM(bundle: HydratedJourneyMapBundle): string {
  const {journeyMap: m, stages, lenses, cells} = bundle;
  const filled = cells.filter((c) => c.content && c.content.trim() !== '').length;
  const confirmed = cells.filter((c) => c.status === 'confirmed').length;
  const locked = cells.filter((c) => c.isLocked).length;
  const total = stages.length * lenses.length;
  const title = m.title || 'Untitled Journey Map';

  const lines: string[] = [];
  lines.push(`# Journey Map: ${title}`, '');
  lines.push(`This document describes the journey map "${title}" exported from Emgram. It is a source-of-truth reference for understanding the stages a primary actor moves through and the perspectives (lenses) considered at each stage.`, '');

  lines.push('## Overview');
  lines.push(`- Title: ${dash(m.title)}`);
  lines.push(`- Status: ${dash(m.status)}`);
  lines.push(`- Intent: ${dash(m.intent)}`);
  lines.push(`- Map level: ${dash(m.map_level)}`);
  lines.push(`- Number of stages: ${stages.length}`);
  lines.push(`- Number of lenses: ${lenses.length}`);
  lines.push(`- Total cells: ${total} (filled: ${filled}, confirmed: ${confirmed}, locked: ${locked})`, '');

  lines.push('## Journey Context');
  for (const [key, label] of settingsFields) lines.push(`- ${label}: ${dash(m[key])}`);
  lines.push('');

  const sai = m.smart_ai_settings;
  if (sai) {
    lines.push('## AI Behaviour Settings');
    lines.push(`- Interview depth: ${dash(sai.interview_depth)}`);
    lines.push(`- Insight standard: ${dash(sai.insight_standard)}`);
    lines.push(`- Lens priority: ${dash(sai.lens_priority)}`);
    lines.push(`- Emotional mapping enabled: ${yesNo(sai.emotional_mapping)}`);
    lines.push(`- Business impact framing enabled: ${yesNo(sai.business_impact_framing)}`);
    lines.push(`- Auto-confirm writes enabled: ${yesNo(sai.auto_confirm_writes)}`, '');
  }

  lines.push('## Stages');
  lines.push('Stages represent the sequential phases of the journey. Each stage has a goal and a primary actor lens.', '');
  stages.forEach((s, i) => {
    lines.push(`### Stage ${i + 1}: ${dash(s.label)}`);
    if (s.stageGoal) lines.push(`Goal: ${s.stageGoal}`);
    if (s.primaryActorLens) lines.push(`Primary actor lens: ${s.primaryActorLens}`);
    lines.push('');
  });

  lines.push('## Lenses (Actors)');
  lines.push('Lenses represent the perspectives or actors considered at each stage.', '');
  for (const l of lenses) {
    lines.push(`### ${dash(l.label)}`);
    if (l.actorType) lines.push(`Actor type: ${l.actorType}`);
    if (l.personaDescription) lines.push(`Persona: ${l.personaDescription}`);
    if (l.primaryGoal) lines.push(`Primary goal: ${l.primaryGoal}`);
    if (l.standingConstraints) lines.push(`Constraints: ${l.standingConstraints}`);
    if (l.rolePrompt) lines.push(`Role prompt: ${l.rolePrompt}`);
    lines.push('');
  }

  lines.push('## Coverage Matrix');
  lines.push('Each cell shows the state of the intersection between a lens (row) and a stage (column). States: confirmed, draft, empty, locked.', '');
  lines.push(renderGrid(stages, lenses, cells), '');

  lines.push('## Cell Details');
  lines.push('Each section below describes one cell at the intersection of a lens and a stage. Cells are listed stage-by-stage in journey order.', '');
  for (const s of stages) {
    for (const l of lenses) {
      const c = cells.find((x) => x.stageId === s.id && x.lensId === l.id);
      lines.push(`### Cell: ${dash(l.label)} during ${dash(s.label)}`);
      lines.push(`This cell describes the perspective of "${dash(l.label)}" during the "${dash(s.label)}" stage.`);
      lines.push(`State: ${cellState(c)}. Locked: ${yesNo(c?.isLocked)}.`);
      lines.push('');
      lines.push(c?.content && c.content.trim() !== '' ? c.content.trim() : 'No content has been captured for this cell.');
      const af = renderActorFields(c?.actorFields);
      if (af) lines.push(af);
      lines.push('');
    }
  }

  lines.push('## Glossary');
  lines.push('This section maps the internal keys used in this journey map to their human-readable labels, so that questions referencing either form can be answered.', '');
  lines.push('Stage keys:');
  for (const s of stages) lines.push(`- ${s.key ?? s.id}: ${dash(s.label)}`);
  lines.push('');
  lines.push('Lens keys:');
  for (const l of lenses) lines.push(`- ${l.key ?? l.id}: ${dash(l.label)}${l.actorType ? ` (actor type: ${l.actorType})` : ''}`);
  lines.push('');

  return lines.join('\n');
}

const NOTEBOOKLM_WORD_LIMIT = 500_000;
const NOTEBOOKLM_WORD_WARN = 450_000;

function countWords(text: string): number {
  const matches = text.match(/[A-Za-z0-9_]+/g);
  return matches ? matches.length : 0;
}

export async function exportJourneyMapNotebookLM(journeyMapId: number, fallbackTitle?: string): Promise<void> {
  const bundle = await loadJourneyMapBundle(journeyMapId);
  const md = buildJourneyMapNotebookLM(bundle);
  const words = countWords(md);
  if (words >= NOTEBOOKLM_WORD_LIMIT) {
    throw new Error(`Journey map export is ${words.toLocaleString()} words, exceeding NotebookLM's 500,000-word source limit. Trim cell content or split the map before exporting.`);
  }
  if (words >= NOTEBOOKLM_WORD_WARN) {
    console.warn(`[NotebookLM export] Journey map is ${words.toLocaleString()} words, approaching the 500,000-word NotebookLM limit.`);
  }
  const filename = `journey_map_${snake(bundle.journeyMap.title || fallbackTitle || `journey_map_${journeyMapId}`)}.md`;
  const blob = new Blob([md], {type: 'text/markdown;charset=utf-8'});
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  setTimeout(() => URL.revokeObjectURL(url), 0);
}
