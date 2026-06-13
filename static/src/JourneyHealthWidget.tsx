import React, { useState } from 'react';
import { X, BarChart2, HelpCircle, Sparkles } from 'lucide-react';
import type { ScorecardResult, HealthLabel } from './xano';

interface Props {
  journeyMapId: number;
  scorecard: ScorecardResult | null;
  baseline: ScorecardResult | null;
  isOpen: boolean;
  onClose: () => void;
  onAiNudge?: (prompt: string) => void;
}

// ── Tooltip (US-MET-15) ──────────────────────────────────────────────────────
function InfoTooltip({ text }: { text: string }) {
  const [show, setShow] = useState(false);
  return (
    <span className="relative inline-flex items-center">
      <HelpCircle
        className="w-3 h-3 text-zinc-300 hover:text-zinc-500 cursor-help ml-0.5"
        onMouseEnter={() => setShow(true)}
        onMouseLeave={() => setShow(false)}
      />
      {show && (
        <span className="absolute left-4 top-0 z-50 w-52 bg-zinc-900 text-white text-[10px] leading-snug rounded-lg px-2.5 py-2 shadow-xl pointer-events-none">
          {text}
        </span>
      )}
    </span>
  );
}

// ── AI Nudge button (US-MET-17) ──────────────────────────────────────────────
function AiNudge({ prompt, onAiNudge }: { prompt: string; onAiNudge?: (p: string) => void }) {
  if (!onAiNudge) return null;
  return (
    <button
      onClick={() => onAiNudge(prompt)}
      className="flex items-center gap-1 text-[9px] text-indigo-500 hover:text-indigo-700 font-medium"
    >
      <Sparkles className="w-2.5 h-2.5" /> Ask AI
    </button>
  );
}

function fmt(n: number | null, decimals = 1): string {
  if (n == null) return '—';
  return n.toFixed(decimals);
}

function fmtMoney(n: number | null): string {
  if (n == null) return '—';
  if (n >= 1_000_000) return `$${(n / 1_000_000).toFixed(1)}M`;
  if (n >= 1_000) return `$${(n / 1_000).toFixed(0)}K`;
  return `$${n.toFixed(0)}`;
}

function Delta({ current, baseline, invert = false }: { current: number | null; baseline: number | null; invert?: boolean }) {
  if (current == null || baseline == null) return null;
  const diff = current - baseline;
  if (Math.abs(diff) < 0.05) return null;
  const positive = invert ? diff < 0 : diff > 0;
  return (
    <span className={`text-[10px] font-medium ${positive ? 'text-emerald-600' : 'text-red-500'}`}>
      {diff > 0 ? '▲' : '▼'} {diff > 0 ? '+' : ''}{diff.toFixed(1)}
    </span>
  );
}

function HealthDot({ hl }: { hl: HealthLabel | null }) {
  if (hl === 'healthy') return <span className="text-emerald-500 text-[10px]">●</span>;
  if (hl === 'at_risk') return <span className="text-amber-500 text-[10px]">●</span>;
  if (hl === 'critical') return <span className="text-red-500 text-[10px]">●</span>;
  return <span className="text-zinc-300 text-[10px]">●</span>;
}

// US-MET-19 — exposed so App.tsx toolbar chip can show the same dot colour without coupling
export { HealthDot };

export function JourneyHealthWidget({ journeyMapId: _journeyMapId, scorecard, baseline, isOpen, onClose, onAiNudge }: Props) {
  const [expanded, setExpanded] = useState(false);

  const mr = scorecard?.metrics_rollup ?? null;
  const fr = scorecard?.financial_rollup ?? null;
  const bMr = baseline?.metrics_rollup ?? null;
  const bFr = baseline?.financial_rollup ?? null;
  const isEmpty = !mr || mr.populated_count === 0;
  const criticalCount = mr ? mr.stages.filter(s => s.health_label === 'critical').length : null;
  const bCriticalCount = bMr ? bMr.stages.filter(s => s.health_label === 'critical').length : null;
  const rar = fr && fr.total_revenue_at_risk > 0 ? fr.total_revenue_at_risk : null;
  const bRar = bFr && bFr.total_revenue_at_risk > 0 ? bFr.total_revenue_at_risk : null;

  return (
    /* US-MET-19 — right sidebar, slides in/out, no drag */
    <div
      className={`fixed right-0 top-12 bottom-0 w-64 bg-white border-l border-zinc-200 shadow-xl z-40 flex flex-col transition-transform duration-200 ease-in-out ${isOpen ? 'translate-x-0' : 'translate-x-full'}`}
    >
      {/* Header */}
      <div className="flex items-center justify-between px-3 py-2 bg-zinc-50 border-b border-zinc-100 shrink-0">
        <div className="flex items-center gap-1.5 text-[11px] font-semibold text-zinc-700">
          <BarChart2 className="w-3.5 h-3.5 text-indigo-500" />
          Journey Health
        </div>
        <div className="flex items-center gap-1">
          <button onClick={() => setExpanded(v => !v)} className="text-[10px] text-zinc-400 hover:text-zinc-600 px-1 cursor-pointer">
            {expanded ? '▲' : '▼'}
          </button>
          <button onClick={onClose} className="p-0.5 hover:bg-zinc-200 rounded text-zinc-400 cursor-pointer">
            <X className="w-3 h-3" />
          </button>
        </div>
      </div>

      <div className="flex-1 overflow-y-auto px-3 py-2 space-y-1.5">
          {/* Phase banner (US-MET-16) — shown when < 3 stages have data */}
          {!isEmpty && mr && mr.populated_count < 3 && (
            <div className="flex items-center gap-1.5 px-2 py-1.5 bg-amber-50 border border-amber-200 rounded-lg">
              <span className="text-[9px] text-amber-700 leading-snug">
                📋 Planning mode — {mr.populated_count} of {mr.total_count} stages have metrics data
              </span>
            </div>
          )}

          {isEmpty ? (
            <div className="py-1 space-y-1.5">
              <p className="text-[10px] text-zinc-400">No metrics yet — add a Metrics lens row to enable</p>
              <AiNudge prompt="populate the Metrics actor role, identity fields, and all stage cell fields — infer from existing actor rows in this map" onAiNudge={onAiNudge} />
            </div>
          ) : (
            <>
              {/* Score row (US-MET-15 tooltip) */}
              <div className="flex items-center justify-between gap-4">
                <div className="flex items-center gap-0.5 text-[10px] text-zinc-500">
                  Score
                  <InfoTooltip text="Average stage_health (1–10) across all Metrics lens cells. Healthy ≥ 8.0. Populated by the Metrics actor row." />
                </div>
                <div className="flex items-center gap-1.5">
                  <span className="text-sm font-bold text-zinc-900">{fmt(mr?.map_health ?? null)}</span>
                  <Delta current={mr?.map_health ?? null} baseline={bMr?.map_health ?? null} />
                  <HealthDot hl={mr?.map_hl ?? null} />
                </div>
              </div>

              {expanded && (
                <>
                  {/* Revenue at Risk row */}
                  <div className="flex items-center justify-between gap-4">
                    <div className="flex items-center gap-0.5 text-[10px] text-zinc-500">
                      Revenue at Risk
                      <InfoTooltip text="Sum of revenue_at_risk from Financial Intelligence cells. Shows — until financial actor fields are populated." />
                    </div>
                    <div className="flex items-center gap-1.5">
                      {rar != null ? (
                        <>
                          <span className="text-sm font-bold text-zinc-900">{fmtMoney(rar)}</span>
                          <Delta current={rar} baseline={bRar} invert />
                        </>
                      ) : (
                        <AiNudge prompt="populate the revenue_at_risk field in the Financial Intelligence cells based on existing financial data in this map" onAiNudge={onAiNudge} />
                      )}
                    </div>
                  </div>

                  {/* Critical Stages row */}
                  <div className="flex items-center justify-between gap-4">
                    <div className="flex items-center gap-0.5 text-[10px] text-zinc-500">
                      Critical Stages
                      <InfoTooltip text="Count of stages where stage_health < 5. Zero is good — means no stages are in a critical state." />
                    </div>
                    <div className="flex items-center gap-1.5">
                      <span className="text-sm font-bold text-zinc-900">{criticalCount ?? '—'}</span>
                      <Delta current={criticalCount} baseline={bCriticalCount} invert />
                    </div>
                  </div>

                  {/* Progress bar (US-MET-18) */}
                  {mr && mr.total_count > 0 && (
                    <div className="pt-1 space-y-1">
                      <div className="flex items-center justify-between text-[9px] text-zinc-400">
                        <span>Metrics coverage</span>
                        <span>{mr.populated_count} / {mr.total_count} stages</span>
                      </div>
                      <div className="h-1 bg-zinc-100 rounded-full overflow-hidden">
                        <div
                          className={`h-full rounded-full transition-all ${mr.populated_count / mr.total_count >= 0.8 ? 'bg-emerald-500' : 'bg-amber-400'}`}
                          style={{ width: `${(mr.populated_count / mr.total_count) * 100}%` }}
                        />
                      </div>
                    </div>
                  )}

                  {/* Per-stage breakdown */}
                  {mr!.stages.filter(s => s.cell_populated).length > 0 && (
                    <div className="pt-1 border-t border-zinc-100 space-y-1">
                      {mr!.stages.filter(s => s.cell_populated).map(s => (
                        <div key={s.stage_id} className="flex items-center justify-between">
                          <span className="text-[9px] text-zinc-400 truncate max-w-[130px]">{s.stage_label}</span>
                          <div className="flex items-center gap-1">
                            <span className="text-[10px] font-medium text-zinc-700">{fmt(s.health)}</span>
                            <HealthDot hl={s.health_label} />
                          </div>
                        </div>
                      ))}
                    </div>
                  )}
                </>
              )}
            </>
          )}
        </div>
        {!isEmpty && (
          <div className="shrink-0 px-3 pb-2 text-[9px] text-zinc-300">Delta since you opened this map</div>
        )}
    </div>
  );
}
