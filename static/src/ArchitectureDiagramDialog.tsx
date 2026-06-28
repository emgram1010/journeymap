// US-EXP-1-13 — Lightweight dialog for "Architecture diagram (.mmd)…"
// Same walker fetch as LinkedSkillExportDialog but no word-budget complexity.

import {X} from 'lucide-react';
import {useEffect, useMemo, useRef, useState} from 'react';
import {fetchLinkedGraph, type LinkedGraph} from './linkedGraphClient';
import {buildArchitectureDiagram} from './exportArchitectureDiagram';
import {filterGraph} from './exportLinkedSkillBundle';
import type {TraversalMode} from './exportLinkedManifest';

interface Props {
  mapId: number;
  mapTitle: string;
  onClose: () => void;
  onError: (msg: string) => void;
  onSuccess?: (summary: {filename: string; nodeCount: number; edgeCount: number}) => void;
}

const OPTIONS: Array<{value: TraversalMode; label: string}> = [
  {value: 'all_linked', label: 'All linked edges'},
  {value: 'sub_only', label: 'Sub-journeys only'},
  {value: 'exception_only', label: 'Exceptions only'},
];

export function ArchitectureDiagramDialog({mapId, mapTitle, onClose, onError, onSuccess}: Props) {
  const [graph, setGraph] = useState<LinkedGraph | null>(null);
  const [loading, setLoading] = useState(true);
  const [traversal, setTraversal] = useState<TraversalMode>('all_linked');
  const [direction, setDirection] = useState<'TD' | 'LR'>('TD');
  const [includeLegend, setIncludeLegend] = useState(true);
  const abortRef = useRef<AbortController | null>(null);

  useEffect(() => {
    const ctrl = new AbortController();
    abortRef.current = ctrl;
    fetchLinkedGraph(mapId, {signal: ctrl.signal})
      .then((g) => { if (!ctrl.signal.aborted) setGraph(g); })
      .catch((e) => {
        if (ctrl.signal.aborted) return;
        onError(e instanceof Error ? e.message : 'Failed to load linked graph');
        onClose();
      })
      .finally(() => { if (!ctrl.signal.aborted) setLoading(false); });
    return () => ctrl.abort();
  }, [mapId, onClose, onError]);

  const counts = useMemo(() => {
    if (!graph) return new Map<TraversalMode, {nodes: number; edges: number}>();
    const out = new Map<TraversalMode, {nodes: number; edges: number}>();
    for (const opt of OPTIONS) {
      const f = filterGraph(graph, opt.value);
      out.set(opt.value, {nodes: f.bfsOrder.length, edges: f.links.length});
    }
    return out;
  }, [graph]);

  const handleDownload = () => {
    if (!graph) return;
    try {
      const result = buildArchitectureDiagram(graph, {traversal, direction, includeLegend});
      const blob = new Blob([result.mermaid], {type: 'text/plain;charset=utf-8'});
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = result.filename;
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      setTimeout(() => URL.revokeObjectURL(url), 0);
      onSuccess?.({filename: result.filename, nodeCount: result.nodeCount, edgeCount: result.edgeCount});
      onClose();
    } catch (err) {
      onError(err instanceof Error ? err.message : 'Diagram export failed');
    }
  };

  return (
    <div className="fixed inset-0 bg-black/30 flex items-center justify-center z-50" onClick={onClose}>
      <div className="bg-white rounded-2xl shadow-xl p-6 w-[480px] max-h-[90vh] overflow-auto" onClick={(e) => e.stopPropagation()}>
        <div className="flex items-start justify-between mb-4">
          <div>
            <h3 className="text-sm font-semibold text-zinc-900">Export architecture diagram</h3>
            <p className="text-xs text-zinc-500 mt-0.5">From <span className="font-mono">m{mapId}</span> · {mapTitle}</p>
          </div>
          <button onClick={onClose} className="p-1 hover:bg-zinc-100 rounded text-zinc-400">
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
                  const c = counts.get(opt.value);
                  return (
                    <label key={opt.value} className={`flex items-center justify-between gap-3 p-2.5 border rounded-lg cursor-pointer ${traversal === opt.value ? 'border-zinc-900 bg-zinc-50' : 'border-zinc-200 hover:border-zinc-300'}`}>
                      <div className="flex items-center gap-2">
                        <input type="radio" name="diagram-traversal" value={opt.value} checked={traversal === opt.value} onChange={() => setTraversal(opt.value)} />
                        <span className="text-xs font-semibold text-zinc-900">{opt.label}</span>
                      </div>
                      {c && <span className="text-[10px] text-zinc-600">{c.nodes} nodes · {c.edges} edges</span>}
                    </label>
                  );
                })}
              </div>
            </div>

            <div className="mb-4 flex items-center gap-4">
              <div>
                <div className="text-[10px] font-semibold uppercase tracking-wide text-zinc-400 mb-1">Direction</div>
                <div className="flex gap-1">
                  <button onClick={() => setDirection('TD')} className={`px-2 py-1 text-[11px] rounded ${direction === 'TD' ? 'bg-zinc-900 text-white' : 'bg-zinc-100 text-zinc-700'}`}>Top → Down</button>
                  <button onClick={() => setDirection('LR')} className={`px-2 py-1 text-[11px] rounded ${direction === 'LR' ? 'bg-zinc-900 text-white' : 'bg-zinc-100 text-zinc-700'}`}>Left → Right</button>
                </div>
              </div>
              <label className="flex items-center gap-2 text-xs text-zinc-700 mt-4">
                <input type="checkbox" checked={includeLegend} onChange={(e) => setIncludeLegend(e.target.checked)} />
                Include legend
              </label>
            </div>

            {graph.warnings.length > 0 && (
              <div className="mb-4 p-3 bg-amber-50 border border-amber-200 rounded-lg">
                <div className="text-[10px] font-semibold uppercase tracking-wide text-amber-700 mb-1">Walker warnings ({graph.warnings.length})</div>
                <ul className="text-[11px] text-amber-800 space-y-0.5">
                  {graph.warnings.map((w, i) => <li key={i}><code className="font-mono">{w.type}</code> — {w.detail}</li>)}
                </ul>
              </div>
            )}

            <div className="flex items-center justify-end gap-2">
              <button onClick={onClose} className="px-3 py-1.5 text-xs text-zinc-600 hover:bg-zinc-100 rounded">Close</button>
              <button onClick={handleDownload} className="px-3 py-1.5 text-xs font-semibold bg-zinc-900 text-white rounded hover:bg-zinc-800">
                Download .mmd
              </button>
            </div>
          </>
        )}
      </div>
    </div>
  );
}
