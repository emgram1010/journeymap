import React, {useCallback, useEffect, useRef, useState} from 'react';
import {AnimatePresence, motion} from 'framer-motion';
import {ArrowLeft, Download, ExternalLink, RotateCcw, Sparkles, X} from 'lucide-react';
import {
  fetchCompareMeta,
  fetchScorecard,
  sendCompareMessage,
  type CompareMapMeta,
  type CompareMessageResponse,
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

// ── Compare Analyst Panel ─────────────────────────────────────────────────────

interface ChatMessage {
  role: 'user' | 'assistant';
  text: string;
}

interface CompareAnalystPanelProps {
  archId: number;
  mapAId: number;
  mapBId: number;
  onClose: () => void;
}

const AUTO_SUMMARY_PROMPT = 'Summarize the key differences between these two scenarios and which one you would recommend focusing on.';

function CompareAnalystPanel({archId, mapAId, mapBId, onClose}: CompareAnalystPanelProps) {
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [input, setInput] = useState('');
  const [isThinking, setIsThinking] = useState(false);
  const [conversationId, setConversationId] = useState<number | null>(null);
  const [error, setError] = useState<string | null>(null);
  const scrollRef = useRef<HTMLDivElement>(null);
  const hasAutoOpened = useRef(false);

  const send = useCallback(async (content: string) => {
    if (!content.trim() || isThinking) return;
    setMessages(prev => [...prev, {role: 'user', text: content}]);
    setInput('');
    setIsThinking(true);
    setError(null);

    try {
      const res: CompareMessageResponse = await sendCompareMessage(archId, mapAId, mapBId, content, conversationId);
      setConversationId(res.conversation_id);
      setMessages(prev => [...prev, {role: 'assistant', text: res.reply}]);
    } catch {
      setError('Something went wrong. Try again.');
      setMessages(prev => prev.slice(0, -1)); // remove optimistic user msg
    } finally {
      setIsThinking(false);
    }
  }, [archId, mapAId, mapBId, conversationId, isThinking]);

  // Auto-summary on first open
  useEffect(() => {
    if (hasAutoOpened.current) return;
    hasAutoOpened.current = true;
    void send(AUTO_SUMMARY_PROMPT);
  }, []); // eslint-disable-line react-hooks/exhaustive-deps

  // Auto-scroll
  useEffect(() => {
    if (scrollRef.current) {
      scrollRef.current.scrollTop = scrollRef.current.scrollHeight;
    }
  }, [messages, isThinking]);

  const handleKeyDown = (e: React.KeyboardEvent<HTMLTextAreaElement>) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      void send(input);
    }
  };

  return (
    <motion.div
      key="compare-analyst-panel"
      initial={{x: '100%', opacity: 0}}
      animate={{x: 0, opacity: 1}}
      exit={{x: '100%', opacity: 0}}
      transition={{type: 'spring', stiffness: 320, damping: 32}}
      className="fixed top-0 right-0 h-full w-96 bg-white border-l border-zinc-200 shadow-2xl z-50 flex flex-col"
    >
      {/* Header */}
      <div className="h-14 flex items-center justify-between px-4 border-b border-zinc-200 shrink-0">
        <div className="flex items-center gap-2">
          <Sparkles className="w-4 h-4 text-indigo-500" />
          <span className="text-sm font-semibold text-zinc-800">Compare Analyst</span>
        </div>
        <button onClick={onClose} className="p-1.5 rounded-lg text-zinc-400 hover:text-zinc-700 hover:bg-zinc-100 transition-colors">
          <X className="w-4 h-4" />
        </button>
      </div>

      {/* Messages */}
      <div ref={scrollRef} className="flex-1 overflow-y-auto px-4 py-4 space-y-4">
        {messages.length === 0 && !isThinking && (
          <p className="text-xs text-zinc-400 text-center mt-8">Loading analysis…</p>
        )}
        {messages.map((msg, i) => (
          <div key={i} className={`flex ${msg.role === 'user' ? 'justify-end' : 'justify-start'} gap-2`}>
            {msg.role === 'assistant' && (
              <div className="w-6 h-6 rounded-full bg-zinc-900 flex items-center justify-center shrink-0 mt-0.5">
                <span className="text-white text-[10px] font-bold">AI</span>
              </div>
            )}
            <div
              className={`max-w-[80%] rounded-2xl px-3 py-2 text-xs leading-relaxed whitespace-pre-wrap ${
                msg.role === 'user'
                  ? 'bg-zinc-900 text-white rounded-tr-sm'
                  : 'bg-zinc-100 text-zinc-800 rounded-tl-sm'
              }`}
            >
              {/* Hide the auto-summary prompt from user-visible messages */}
              {msg.role === 'user' && msg.text === AUTO_SUMMARY_PROMPT ? null : msg.text}
            </div>
          </div>
        ))}
        {isThinking && (
          <div className="flex items-center gap-2">
            <div className="w-6 h-6 rounded-full bg-zinc-900 flex items-center justify-center shrink-0">
              <span className="text-white text-[10px] font-bold">AI</span>
            </div>
            <div className="flex gap-1 px-3 py-2 bg-zinc-100 rounded-2xl rounded-tl-sm">
              {[0, 1, 2].map(d => (
                <span key={d} className="w-1.5 h-1.5 bg-zinc-400 rounded-full animate-bounce" style={{animationDelay: `${d * 150}ms`}} />
              ))}
            </div>
          </div>
        )}
        {error && <p className="text-xs text-rose-500 text-center">{error}</p>}
      </div>

      {/* Input */}
      <div className="shrink-0 px-4 py-3 border-t border-zinc-200">
        <div className="flex items-end gap-2 bg-zinc-50 border border-zinc-200 rounded-xl px-3 py-2">
          <textarea
            value={input}
            onChange={e => setInput(e.target.value)}
            onKeyDown={handleKeyDown}
            placeholder="Ask about this comparison…"
            rows={1}
            className="flex-1 resize-none bg-transparent text-xs text-zinc-800 placeholder-zinc-400 outline-none leading-relaxed"
          />
          <button
            onClick={() => void send(input)}
            disabled={!input.trim() || isThinking}
            className="shrink-0 w-7 h-7 rounded-lg bg-zinc-900 text-white flex items-center justify-center disabled:opacity-30 hover:bg-zinc-700 transition-colors"
          >
            <svg className="w-3.5 h-3.5" viewBox="0 0 16 16" fill="currentColor">
              <path d="M14.854 1.146a.5.5 0 0 0-.707 0L8 7.293 1.854 1.146a.5.5 0 0 0-.707.707l6.5 6.5a.5.5 0 0 0 .707 0l6.5-6.5a.5.5 0 0 0 0-.707z"/>
              <path d="M14.854 8.146a.5.5 0 0 0-.707 0L8 14.293 1.854 8.146a.5.5 0 0 0-.707.707l6.5 6.5a.5.5 0 0 0 .707 0l6.5-6.5a.5.5 0 0 0 0-.707z"/>
            </svg>
          </button>
        </div>
      </div>
    </motion.div>
  );
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
  archId: number;
  metaA: CompareMapMeta; metaB: CompareMapMeta;
  scoreA: ScorecardResult; scoreB: ScorecardResult;
  onBack: () => void; onOpenJourney: (id: number) => void;
}

function CompareLoaded({archId, metaA, metaB, scoreA, scoreB, onBack, onOpenJourney}: LoadedProps) {
  const [chatOpen, setChatOpen] = useState(false);
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
    <div className="pb-12 relative">
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
      {/* Floating Ask AI button */}
      <button
        onClick={() => setChatOpen(true)}
        className="fixed bottom-6 right-6 z-40 flex items-center gap-2 px-4 py-3 bg-zinc-900 text-white text-xs font-semibold rounded-full shadow-lg hover:bg-zinc-800 transition-colors"
      >
        <Sparkles className="w-3.5 h-3.5 text-indigo-400" />
        Ask AI
        <span className="w-2 h-2 rounded-full bg-amber-400 animate-pulse" />
      </button>

      {/* Compare Analyst Chat Panel */}
      <AnimatePresence>
        {chatOpen && (
          <CompareAnalystPanel
            archId={archId}
            mapAId={metaA.id}
            mapBId={metaB.id}
            onClose={() => setChatOpen(false)}
          />
        )}
      </AnimatePresence>
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

  return <CompareLoaded archId={archId} metaA={metaA} metaB={metaB} scoreA={scoreA} scoreB={scoreB} onBack={onBack} onOpenJourney={onOpenJourney} />;
}
