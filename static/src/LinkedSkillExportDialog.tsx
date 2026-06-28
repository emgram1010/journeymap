// US-EXP-1-09 + US-EXP-1-15 — Traversal picker dialog for linked exports.
// Variant 'skill' → exportLinkedSkillBundle (.zip folder tree)
// Variant 'notebooklm' → exportLinkedNotebookLM (.zip flat per-map MDs)
// Fetches the linked graph once, then filters in memory per radio change.

import {X} from 'lucide-react';
import {useEffect, useMemo, useRef, useState} from 'react';
import {fetchLinkedGraph, type LinkedGraph} from './linkedGraphClient';
import {classifyFit, computeWordBudget, type FitBadge} from './linkedGraphBudget';
import {buildLinkedSkillBundle, filterGraph} from './exportLinkedSkillBundle';
import {buildLinkedNotebookLMBundle} from './exportLinkedNotebookLM';
import type {TraversalMode} from './exportLinkedManifest';

export type LinkedExportVariant = 'skill' | 'notebooklm';

export interface LinkedSkillExportSummary {
  filename: string;
  mapCount: number;
  wordCount: number;
  warningCount: number;
  cancelled: boolean;
  variant: LinkedExportVariant;
}

interface Props {
  mapId: number;
  mapTitle: string;
  variant?: LinkedExportVariant;
  onClose: () => void;
  onError: (msg: string) => void;
  onSuccess?: (summary: LinkedSkillExportSummary) => void;
}

const VARIANT_COPY: Record<LinkedExportVariant, {title: string}> = {
  skill: {title: 'Export linked skill bundle'},
  notebooklm: {title: 'Export linked NotebookLM bundle'},
};

const OPTIONS: Array<{value: TraversalMode; label: string; hint: string}> = [
  {value: 'all_linked', label: 'All linked', hint: 'sub_journey + exception + anti_journey + agent_manual'},
  {value: 'sub_only', label: 'Sub-journeys only', hint: 'sub_journey + agent_manual'},
  {value: 'exception_only', label: 'Exceptions only', hint: 'exception edges only'},
];

const BADGE_TEXT: Record<FitBadge, string> = {green: '🟢', yellow: '🟡', red: '🔴'};

function formatCount(n: number): string {
  if (n >= 1000) return `${(n / 1000).toFixed(1)}k`;
  return String(n);
}

export function LinkedSkillExportDialog({mapId, mapTitle, variant = 'skill', onClose, onError, onSuccess}: Props) {
  const [graph, setGraph] = useState<LinkedGraph | null>(null);
  const [loading, setLoading] = useState(true);
  const [traversal, setTraversal] = useState<TraversalMode>('all_linked');
  const [includeGlossary, setIncludeGlossary] = useState(true);
  const [exporting, setExporting] = useState(false);
  const [cancelling, setCancelling] = useState(false);
  const [phaseLabel, setPhaseLabel] = useState<string>('');
  const abortRef = useRef<AbortController | null>(null);
  const cancelRef = useRef(false);

  useEffect(() => {
    const ctrl = new AbortController();
    abortRef.current = ctrl;
    fetchLinkedGraph(mapId, {signal: ctrl.signal})
      .then((g) => {
        if (!ctrl.signal.aborted) setGraph(g);
      })
      .catch((e) => {
        if (ctrl.signal.aborted) return;
        onError(e instanceof Error ? e.message : 'Failed to load linked graph');
        onClose();
      })
      .finally(() => {
        if (!ctrl.signal.aborted) setLoading(false);
      });
    return () => ctrl.abort();
  }, [mapId, onClose, onError]);

  const perOption = useMemo(() => {
    if (!graph) return new Map<TraversalMode, {maps: number; words: number; badge: FitBadge}>();
    const out = new Map<TraversalMode, {maps: number; words: number; badge: FitBadge}>();
    for (const opt of OPTIONS) {
      const filtered = filterGraph(graph, opt.value);
      const budget = computeWordBudget(filtered);
      out.set(opt.value, {maps: filtered.bfsOrder.length, words: budget.total, badge: classifyFit(budget.total)});
    }
    return out;
  }, [graph]);

  const currentStats = perOption.get(traversal);
  const isRed = currentStats?.badge === 'red';
  const splitPlan = useMemo(() => {
    if (!graph || !isRed) return null;
    return computeWordBudget(filterGraph(graph, traversal)).splitPlan ?? null;
  }, [graph, traversal, isRed]);

  const handleDownload = async () => {
    if (!graph || isRed) return;
    cancelRef.current = false;
    setCancelling(false);
    setExporting(true);
    setPhaseLabel('Building markdown…');
    try {
      const onPhase = (phase: 'building' | 'zipping', done: number, total: number) => {
        setPhaseLabel(phase === 'building' ? `Building ${done}/${total} maps…` : 'Zipping…');
      };
      const result =
        variant === 'notebooklm'
          ? await buildLinkedNotebookLMBundle(graph, {traversal, shouldCancel: () => cancelRef.current}, onPhase)
          : await buildLinkedSkillBundle(graph, {traversal, includeGlossary, shouldCancel: () => cancelRef.current}, onPhase);
      if (result.cancelled || !result.blob) {
        onSuccess?.({filename: result.filename, mapCount: 0, wordCount: 0, warningCount: result.manifest.warnings.length, cancelled: true, variant});
        onClose();
        return;
      }
      const url = URL.createObjectURL(result.blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = result.filename;
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      setTimeout(() => URL.revokeObjectURL(url), 0);
      onSuccess?.({
        filename: result.filename,
        mapCount: result.manifest.maps.length,
        wordCount: currentStats?.words ?? 0,
        warningCount: result.manifest.warnings.length,
        cancelled: false,
        variant,
      });
      onClose();
    } catch (err) {
      onError(err instanceof Error ? err.message : 'Export failed');
    } finally {
      setExporting(false);
      setCancelling(false);
      setPhaseLabel('');
    }
  };

  const handleCancelClick = () => {
    if (exporting) {
      cancelRef.current = true;
      setCancelling(true);
      setPhaseLabel('Cancelling…');
    } else {
      onClose();
    }
  };

  return (
    <div className="fixed inset-0 bg-black/30 flex items-center justify-center z-50" onClick={exporting ? undefined : onClose}>
      <div className="bg-white rounded-2xl shadow-xl p-6 w-[520px] max-h-[90vh] overflow-auto" onClick={(e) => e.stopPropagation()}>
        <div className="flex items-start justify-between mb-4">
          <div>
            <h3 className="text-sm font-semibold text-zinc-900">{VARIANT_COPY[variant].title}</h3>
            <p className="text-xs text-zinc-500 mt-0.5">From <span className="font-mono">m{mapId}</span> · {mapTitle}</p>
          </div>
          <button onClick={onClose} disabled={exporting} className="p-1 hover:bg-zinc-100 rounded text-zinc-400 disabled:opacity-40">
            <X className="w-4 h-4" />
          </button>
        </div>

        {loading && <div className="text-xs text-zinc-500 py-6 text-center">Walking architecture…</div>}

        {!loading && graph && (
          <>
            <div className="mb-4">
              <div className="text-[10px] font-semibold uppercase tracking-wide text-zinc-400 mb-2">Traversal</div>
              <div className="space-y-2">
                {OPTIONS.map((opt) => {
                  const stats = perOption.get(opt.value);
                  return (
                    <label key={opt.value} className={`flex items-start gap-3 p-3 border rounded-lg cursor-pointer transition-colors ${traversal === opt.value ? 'border-zinc-900 bg-zinc-50' : 'border-zinc-200 hover:border-zinc-300'}`}>
                      <input type="radio" name="traversal" value={opt.value} checked={traversal === opt.value} onChange={() => setTraversal(opt.value)} disabled={exporting} className="mt-0.5" />
                      <div className="flex-1 min-w-0">
                        <div className="flex items-center justify-between gap-2">
                          <span className="text-xs font-semibold text-zinc-900">{opt.label}</span>
                          {stats && <span className="text-[10px] text-zinc-600">{stats.maps} maps · {formatCount(stats.words)} words {BADGE_TEXT[stats.badge]}</span>}
                        </div>
                        <div className="text-[10px] text-zinc-500 mt-0.5">{opt.hint}</div>
                      </div>
                    </label>
                  );
                })}
              </div>
            </div>

            <div className="mb-4">
              <div className="text-[10px] font-semibold uppercase tracking-wide text-zinc-400 mb-2">Output</div>
              <label className="flex items-center gap-2 text-xs text-zinc-700 mb-1">
                <input type="checkbox" checked disabled />
                {variant === 'notebooklm'
                  ? <>One Markdown file per map (NotebookLM source) <span className="text-zinc-400">(always on)</span></>
                  : <>Origin blocks + cross-reference anchors <span className="text-zinc-400">(always on)</span></>}
              </label>
              {variant === 'skill' && (
                <label className="flex items-center gap-2 text-xs text-zinc-700 mb-1">
                  <input type="checkbox" checked={includeGlossary} onChange={(e) => setIncludeGlossary(e.target.checked)} disabled={exporting} />
                  Include <code className="font-mono">GLOSSARY.md</code> primer
                </label>
              )}
              {variant === 'skill' && (
                <label className="flex items-center gap-2 text-xs text-zinc-400">
                  <input type="checkbox" disabled />
                  Inline Mermaid diagram in <code className="font-mono">ARCHITECTURE.md</code> <span>(US-EXP-1-13)</span>
                </label>
              )}
            </div>

            {graph.warnings.length > 0 && (
              <div className="mb-4 p-3 bg-amber-50 border border-amber-200 rounded-lg">
                <div className="text-[10px] font-semibold uppercase tracking-wide text-amber-700 mb-1">Walker warnings ({graph.warnings.length})</div>
                <ul className="text-[11px] text-amber-800 space-y-0.5">
                  {graph.warnings.map((w, i) => (
                    <li key={i}><code className="font-mono">{w.type}</code> — {w.detail}</li>
                  ))}
                </ul>
              </div>
            )}

            {isRed && splitPlan && (
              <div className="mb-4 p-3 bg-red-50 border border-red-200 rounded-lg">
                <div className="text-[10px] font-semibold uppercase tracking-wide text-red-700 mb-1">Over NotebookLM limit (500K words)</div>
                <p className="text-[11px] text-red-800 mb-2">Suggested split into {splitPlan.length} bundles:</p>
                <ul className="text-[11px] text-red-800 space-y-0.5">
                  {splitPlan.map((b, i) => (
                    <li key={i}>Bundle {i + 1}: root m{b.rootMapId} · {b.includedMaps.length} maps · {formatCount(b.wordCount)} words</li>
                  ))}
                </ul>
              </div>
            )}

            <div className="flex items-center justify-between gap-3">
              <div className="text-[11px] text-zinc-500 min-h-[16px]">{exporting ? phaseLabel : ''}</div>
              <div className="flex items-center gap-2">
                <button onClick={handleCancelClick} disabled={cancelling} className="px-3 py-1.5 text-xs text-zinc-600 hover:bg-zinc-100 rounded disabled:opacity-40">
                  {exporting ? (cancelling ? 'Cancelling…' : 'Cancel') : 'Close'}
                </button>
                <button onClick={handleDownload} disabled={exporting || isRed} className="px-3 py-1.5 text-xs font-semibold bg-zinc-900 text-white rounded hover:bg-zinc-800 disabled:opacity-40 disabled:cursor-not-allowed">
                  {exporting ? 'Exporting…' : 'Download .zip'}
                </button>
              </div>
            </div>
          </>
        )}
      </div>
    </div>
  );
}
