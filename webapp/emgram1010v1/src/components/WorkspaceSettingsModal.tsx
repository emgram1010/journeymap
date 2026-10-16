import { useState, useEffect } from 'react';
import { X, CalendarRange, Bot, Settings as SettingsIcon } from 'lucide-react';
import { Workspace } from '../types';
import { getDaysDifference } from '../utils/dateUtils';

interface WorkspaceSettingsModalProps {
  isOpen: boolean;
  workspace: Workspace | null;
  onClose: () => void;
  onSave: (workspaceId: string, updates: Partial<Workspace>) => void;
  onOpenGlobalSettings: () => void;
}

export function WorkspaceSettingsModal({
  isOpen,
  workspace,
  onClose,
  onSave,
  onOpenGlobalSettings,
}: WorkspaceSettingsModalProps) {
  const [windowStart, setWindowStart] = useState('');
  const [windowEnd, setWindowEnd] = useState('');
  const [inputTpm, setInputTpm] = useState(0);
  const [outputTpm, setOutputTpm] = useState(0);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!isOpen || !workspace) return;
    setWindowStart(workspace.planningWindowStart);
    setWindowEnd(workspace.planningWindowEnd);
    setInputTpm(workspace.inputTokensPerMinute);
    setOutputTpm(workspace.outputTokensPerMinute);
    setError(null);
  }, [isOpen, workspace]);

  useEffect(() => {
    if (!isOpen) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose();
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [isOpen, onClose]);

  if (!isOpen || !workspace) return null;

  const windowDays = getDaysDifference(windowStart, windowEnd);

  const handleSave = () => {
    if (!windowStart || !windowEnd) {
      setError('Both window dates are required.');
      return;
    }
    if (windowEnd < windowStart) {
      setError('Window end must be on or after the window start.');
      return;
    }
    onSave(workspace.id, {
      planningWindowStart: windowStart,
      planningWindowEnd: windowEnd,
      inputTokensPerMinute: inputTpm,
      outputTokensPerMinute: outputTpm,
    });
    onClose();
  };

  return (
    <div
      id="workspace-settings-modal-overlay"
      className="fixed inset-0 z-50 bg-neutral-950/40 backdrop-blur-xs flex items-center justify-center p-4 animate-in fade-in duration-100"
      onClick={onClose}
    >
      <div
        id="workspace-settings-modal"
        className="bg-white rounded-lg shadow-xl border border-neutral-200 w-full max-w-lg flex flex-col max-h-[85vh] overflow-hidden animate-in zoom-in-95 duration-100"
        onClick={e => e.stopPropagation()}
      >
        {/* Header */}
        <div className="h-14 px-6 border-b border-neutral-200 flex items-center justify-between bg-neutral-50 shrink-0">
          <div className="flex flex-col">
            <h2 className="text-sm font-bold text-neutral-900">Workspace Settings</h2>
            <span className="text-[11px] text-neutral-500 truncate max-w-xs">{workspace.name}</span>
          </div>
          <button
            type="button"
            onClick={onClose}
            className="p-1 rounded-md text-neutral-400 hover:text-neutral-700 hover:bg-neutral-200/50"
            aria-label="Close workspace settings"
          >
            <X className="w-4 h-4" />
          </button>
        </div>

        {/* Body */}
        <div className="p-6 overflow-y-auto flex flex-col gap-6">
          {/* Planning window */}
          <section>
            <div className="flex items-center gap-1.5 mb-1">
              <CalendarRange className="w-3.5 h-3.5 text-neutral-500" />
              <h3 className="text-xs font-semibold text-neutral-900">Planning window</h3>
            </div>
            <p className="text-[11px] text-neutral-500 mb-2">
              The date range this workspace plans across. Drives the Schedule Grid, its
              paging bounds, and every capacity and cost figure in Plan Health.
            </p>
            <div className="flex items-end gap-3">
              <label className="flex flex-col gap-1">
                <span className="text-[11px] text-neutral-600">Start</span>
                <input
                  id="workspace-window-start"
                  type="date"
                  value={windowStart}
                  onChange={e => { setWindowStart(e.target.value); setError(null); }}
                  className="text-xs px-3 py-2 border border-neutral-200 rounded-md focus:outline-none focus:border-neutral-900 font-mono bg-white"
                />
              </label>
              <label className="flex flex-col gap-1">
                <span className="text-[11px] text-neutral-600">End</span>
                <input
                  id="workspace-window-end"
                  type="date"
                  value={windowEnd}
                  onChange={e => { setWindowEnd(e.target.value); setError(null); }}
                  className="text-xs px-3 py-2 border border-neutral-200 rounded-md focus:outline-none focus:border-neutral-900 font-mono bg-white"
                />
              </label>
              <span className="text-[11px] text-neutral-500 pb-2.5 font-mono">
                {windowDays} days
              </span>
            </div>
            {error && <p className="text-[11px] text-red-600 mt-1.5">{error}</p>}
          </section>

          {/* Throughput */}
          <section>
            <div className="flex items-center gap-1.5 mb-1">
              <Bot className="w-3.5 h-3.5 text-neutral-500" />
              <h3 className="text-xs font-semibold text-neutral-900">AI throughput</h3>
            </div>
            <p className="text-[11px] text-neutral-500 mb-2">
              Plans are scheduled in minutes, but models are billed per token. These
              assumptions convert an AI agent's planned minutes into token volume —
              they're per workspace because how token-intensive the work is depends on
              the project.
            </p>
            <div className="flex items-center gap-4">
              <label className="flex flex-col gap-1">
                <span className="text-[11px] text-neutral-600">Input tokens / min</span>
                <input
                  type="number"
                  min={0}
                  step={100}
                  value={inputTpm}
                  onChange={e => setInputTpm(Number(e.target.value) || 0)}
                  className="w-32 text-xs px-3 py-2 border border-neutral-200 rounded-md focus:outline-none focus:border-neutral-900 font-mono"
                />
              </label>
              <label className="flex flex-col gap-1">
                <span className="text-[11px] text-neutral-600">Output tokens / min</span>
                <input
                  type="number"
                  min={0}
                  step={100}
                  value={outputTpm}
                  onChange={e => setOutputTpm(Number(e.target.value) || 0)}
                  className="w-32 text-xs px-3 py-2 border border-neutral-200 rounded-md focus:outline-none focus:border-neutral-900 font-mono"
                />
              </label>
            </div>
          </section>

          {/* Pointer to the global half */}
          <section className="border-t border-neutral-100 pt-4">
            <p className="text-[11px] text-neutral-500">
              Hourly rates, currency, and model token pricing apply across every
              workspace and live in{' '}
              <button
                type="button"
                onClick={() => { onClose(); onOpenGlobalSettings(); }}
                className="inline-flex items-center gap-1 text-neutral-700 underline decoration-dotted underline-offset-2 hover:text-neutral-900 font-medium"
              >
                <SettingsIcon className="w-3 h-3" />
                global Settings
              </button>
              .
            </p>
          </section>
        </div>

        {/* Footer */}
        <div className="h-14 px-6 border-t border-neutral-200 flex items-center justify-end gap-3 bg-neutral-50 shrink-0">
          <button
            type="button"
            onClick={onClose}
            className="px-3.5 py-1.5 text-xs text-neutral-600 hover:text-neutral-900 font-medium rounded hover:bg-neutral-200/50"
          >
            Cancel
          </button>
          <button
            id="save-workspace-settings-btn"
            type="button"
            onClick={handleSave}
            className="px-4 py-1.5 bg-neutral-900 text-white rounded-md text-xs font-semibold hover:bg-neutral-800 transition-colors shadow-xs"
          >
            Save settings
          </button>
        </div>
      </div>
    </div>
  );
}
