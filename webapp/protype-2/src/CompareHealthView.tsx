import React, {useEffect, useState} from 'react';
import {ArrowLeft, RotateCcw, ExternalLink, Download} from 'lucide-react';
import {
  fetchCompareMeta,
  fetchScorecard,
  type CompareMapMeta,
  type ScorecardResult,
  type ScorecardStage,
} from './xano';

// ── Utilities ────────────────────────────────────────────────────────────────

type Color = 'green' | 'red' | 'black';
type Direction = 'higher' | 'lower';

function colorize(a: number | null, b: number | null, dir: Direction): [Color, Color] {
  if (a === null || b === null) return ['black', 'black'];
  if (a === b) return ['black', 'black'];
  const aWins = dir === 'higher' ? a > b : a < b;
  return aWins ? ['green', 'red'] : ['red', 'green'];
}

const colorClass: Record<Color, string> = {
  green: 'text-emerald-600 font-semibold',
  red: 'text-rose-600 font-semibold',
  black: 'text-zinc-700',
};

function fmt(v: number | null, type: 'health' | 'currency' | 'count'): string {
  if (v === null) return '—';
  if (type === 'health') return v.toFixed(1);
  if (type === 'currency') {
    if (v >= 1_000_000) return `$${(v / 1_000_000).toFixed(1)}M`;
    if (v >= 1_000) return `$${(v / 1_000).toFixed(0)}k`;
    return `$${v}`;
  }
  return String(v);
}

function relativeTime(v: string | number | null | undefined): string {
  if (!v) return '—';
  const ms = typeof v === 'number' ? v : Date.parse(String(v));
  if (isNaN(ms)) return '—';
  const days = Math.floor((Date.now() - ms) / 86_400_000);
  if (days === 0) return 'Today';
  if (days === 1) return 'Yesterday';
  return `${days}d ago`;
}

// ── Types ────────────────────────────────────────────────────────────────────

interface MetricRow {
  label: string;
  aVal: number | null;
  bVal: number | null;
  dir: Direction;
  type: 'health' | 'currency' | 'count';
}

interface CompareHealthViewProps {
  archId: number;
  mapAId: number;
  mapBId: number;
  onBack: () => void;
  onOpenJourney: (mapId: number) => void;
}

// ── Component ────────────────────────────────────────────────────────────────

// ── Inner loaded component (avoids null guards everywhere) ───────────────────

interface LoadedProps {
  metaA: CompareMapMeta; metaB: CompareMapMeta;
  scoreA: ScorecardResult; scoreB: ScorecardResult;
  onBack: () => void; onOpenJourney: (id: number) => void;
}

function CompareLoaded({metaA, metaB, scoreA, scoreB, onBack, onOpenJourney}: LoadedProps) {
  const stagesA = scoreA.metrics_rollup.stages;
  const stagesB = scoreB.metrics_rollup.stages;

  // Align stages by key — union of both, preserving order (A first, then B-only keys)
  const seenKeys = new Set<string>();
  const allStages: {key: string; label: string; stageA: ScorecardStage | null; stageB: ScorecardStage | null}[] = [];
  for (const s of [...stagesA, ...stagesB]) {
    if (!seenKeys.has(s.stage_key)) {
      seenKeys.add(s.stage_key);
      allStages.push({
        key: s.stage_key,
        label: s.stage_label,
        stageA: stagesA.find(x => x.stage_key === s.stage_key) ?? null,
        stageB: stagesB.find(x => x.stage_key === s.stage_key) ?? null,
      });
    }
  }

  const criticalA = stagesA.some(s => s.health !== null)
    ? stagesA.filter(s => s.health_label === 'critical').length : null;
  const criticalB = stagesB.some(s => s.health !== null)
    ? stagesB.filter(s => s.health_label === 'critical').length : null;

  const rows: MetricRow[] = [
    {label: 'JOURNEY HEALTH', aVal: scoreA.metrics_rollup.map_health, bVal: scoreB.metrics_rollup.map_health, dir: 'higher', type: 'health'},
    ...allStages.map(s => ({
      label: `STAGE: ${s.label}`,
      aVal: s.stageA?.health ?? null,
      bVal: s.stageB?.health ?? null,
      dir: 'higher' as Direction,
      type: 'health' as const,
    })),
    {label: 'REVENUE AT RISK', aVal: scoreA.financial_rollup.total_revenue_at_risk || null, bVal: scoreB.financial_rollup.total_revenue_at_risk || null, dir: 'lower', type: 'currency'},
    {label: 'CRITICAL STAGES', aVal: criticalA, bVal: criticalB, dir: 'lower', type: 'count'},
  ];

  const allNull = rows.every(r => r.aVal === null && r.bVal === null);

  // Export CSV
  const handleExport = () => {
    const lines = [
      ['Metric', metaA.title, metaB.title].join(','),
      ...rows.map(r => [r.label, r.aVal ?? '', r.bVal ?? ''].join(',')),
    ].join('\n');
    const blob = new Blob([lines], {type: 'text/csv'});
    const a = document.createElement('a');
    a.href = URL.createObjectURL(blob);
    a.download = `compare-${metaA.id}-${metaB.id}.csv`;
    a.click();
  };

  return (
    <div className="pb-12">
      {/* Header */}
      <div className="flex items-center justify-between mb-6">
        <div className="flex items-center gap-2 text-xs text-zinc-500">
          <button onClick={onBack} className="flex items-center gap-1 hover:text-zinc-900 transition-colors">
            <ArrowLeft className="w-3.5 h-3.5" /><span className="font-medium">Scenarios</span>
          </button>
          <span className="text-zinc-300">|</span>
          <span className="font-semibold text-zinc-700">Compare Health (2)</span>
        </div>
        <button onClick={handleExport}
          className="inline-flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium border border-zinc-200 rounded-lg text-zinc-600 hover:bg-zinc-50 transition-colors">
          <Download className="w-3.5 h-3.5" />Export CSV
        </button>
      </div>

      {allNull && (
        <div className="mb-4 px-4 py-3 bg-amber-50 border border-amber-200 rounded-xl text-xs text-amber-700 text-center">
          Fill in your scenarios with journey health data to compare them.
        </div>
      )}

      {/* Comparison table */}
      <div className="border border-zinc-200 rounded-xl overflow-hidden bg-white">
        <table className="w-full text-xs">
          <thead>
            <tr className="border-b border-zinc-200 bg-zinc-50">
              <th className="text-left px-5 py-4 text-zinc-400 font-semibold uppercase tracking-wider w-48" />
              <th className="px-5 py-4 text-center">
                <p className="font-semibold text-zinc-800 text-sm">{metaA.title}</p>
                <p className="text-zinc-400 text-[11px] mt-0.5">Last modified {relativeTime(metaA.updated_at)}</p>
              </th>
              <th className="px-5 py-4 text-center border-l border-zinc-100">
                <p className="font-semibold text-zinc-800 text-sm">{metaB.title}</p>
                <p className="text-zinc-400 text-[11px] mt-0.5">Last modified {relativeTime(metaB.updated_at)}</p>
              </th>
            </tr>
          </thead>
          <tbody>
            {rows.map((row, i) => {
              const [cA, cB] = colorize(row.aVal, row.bVal, row.dir);
              const isStage = row.label.startsWith('STAGE:');
              return (
                <tr key={row.label} className={`border-b border-zinc-100 last:border-0 ${i % 2 === 0 ? '' : 'bg-zinc-50/40'}`}>
                  <td className={`px-5 py-3 font-semibold uppercase tracking-wider text-zinc-400 ${isStage ? 'pl-8 text-[10px]' : 'text-[11px]'}`}>
                    {row.label}
                  </td>
                  <td className={`px-5 py-3 text-center text-sm ${colorClass[cA]}`}>
                    {fmt(row.aVal, row.type)}
                  </td>
                  <td className={`px-5 py-3 text-center text-sm border-l border-zinc-100 ${colorClass[cB]}`}>
                    {fmt(row.bVal, row.type)}
                  </td>
                </tr>
              );
            })}
          </tbody>
          <tfoot>
            <tr className="border-t border-zinc-200 bg-zinc-50">
              <td className="px-5 py-4" />
              <td className="px-5 py-4 text-center">
                <button onClick={() => onOpenJourney(metaA.id)}
                  className="inline-flex items-center gap-1.5 px-4 py-2 bg-zinc-900 text-white text-xs font-semibold rounded-xl hover:bg-zinc-800 transition-colors">
                  <ExternalLink className="w-3.5 h-3.5" />Open Journey
                </button>
              </td>
              <td className="px-5 py-4 text-center border-l border-zinc-100">
                <button onClick={() => onOpenJourney(metaB.id)}
                  className="inline-flex items-center gap-1.5 px-4 py-2 bg-zinc-900 text-white text-xs font-semibold rounded-xl hover:bg-zinc-800 transition-colors">
                  <ExternalLink className="w-3.5 h-3.5" />Open Journey
                </button>
              </td>
            </tr>
          </tfoot>
        </table>
      </div>
    </div>
  );
}

export default function CompareHealthView({archId, mapAId, mapBId, onBack, onOpenJourney}: CompareHealthViewProps) {
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [metaA, setMetaA] = useState<CompareMapMeta | null>(null);
  const [metaB, setMetaB] = useState<CompareMapMeta | null>(null);
  const [scoreA, setScoreA] = useState<ScorecardResult | null>(null);
  const [scoreB, setScoreB] = useState<ScorecardResult | null>(null);

  useEffect(() => {
    void (async () => {
      setIsLoading(true); setError(null);
      try {
        const [meta, sA, sB] = await Promise.all([
          fetchCompareMeta(archId, mapAId, mapBId),
          fetchScorecard(mapAId),
          fetchScorecard(mapBId),
        ]);
        setMetaA(meta.map_a); setMetaB(meta.map_b);
        setScoreA(sA); setScoreB(sB);
      } catch {
        setError('Unable to load comparison. Please try again.');
      } finally {
        setIsLoading(false);
      }
    })();
  }, [archId, mapAId, mapBId]);

  if (isLoading) return (
    <div className="flex items-center justify-center py-24">
      <RotateCcw className="w-5 h-5 text-zinc-300 animate-spin" />
    </div>
  );

  if (error || !metaA || !metaB || !scoreA || !scoreB) return (
    <div className="flex flex-col items-center justify-center py-20 text-center">
      <p className="text-sm text-zinc-500 mb-4">{error ?? 'Something went wrong.'}</p>
      <button onClick={onBack} className="text-xs font-semibold text-indigo-600 hover:underline">← Back to Scenarios</button>
    </div>
  );

  return <CompareLoaded metaA={metaA} metaB={metaB} scoreA={scoreA} scoreB={scoreB} onBack={onBack} onOpenJourney={onOpenJourney} />;
}
