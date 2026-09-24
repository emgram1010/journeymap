import { useState, useEffect } from 'react';
import { X, Plus, Trash2, User, Settings as SettingsIcon } from 'lucide-react';
import { AppSettings, ModelPricing, Throughput } from '../types';
import { formatMoney } from '../utils/costUtils';

interface SettingsModalProps {
  isOpen: boolean;
  settings: AppSettings;
  /** Active workspace's throughput — used only to show an indicative $/hr. */
  throughput: Throughput;
  onClose: () => void;
  onSave: (settings: AppSettings) => void;
}

export function SettingsModal({ isOpen, settings, throughput, onClose, onSave }: SettingsModalProps) {
  const [draft, setDraft] = useState<AppSettings>(settings);

  // Re-seed the form whenever the modal opens so a cancelled edit doesn't
  // leak into the next session.
  useEffect(() => {
    if (isOpen) setDraft(settings);
  }, [isOpen, settings]);

  useEffect(() => {
    if (!isOpen) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose();
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [isOpen, onClose]);

  if (!isOpen) return null;

  const updateModel = (id: string, patch: Partial<ModelPricing>) => {
    setDraft(prev => ({
      ...prev,
      models: prev.models.map(m => (m.id === id ? { ...m, ...patch } : m)),
    }));
  };

  const addCustomModel = () => {
    setDraft(prev => ({
      ...prev,
      models: [
        ...prev.models,
        {
          id: `custom-${Date.now()}`,
          label: 'Custom model',
          inputPer1M: 0,
          outputPer1M: 0,
          isCustom: true,
        },
      ],
    }));
  };

  const removeModel = (id: string) => {
    setDraft(prev => ({ ...prev, models: prev.models.filter(m => m.id !== id) }));
  };

  // Effective $/hr for a model under the *active workspace's* throughput —
  // shown inline so token rates connect to something comparable with the
  // human rate. Other workspaces with different throughput will differ.
  const modelHourlyRate = (m: ModelPricing) => {
    const perMinute =
      (throughput.inputTokensPerMinute * m.inputPer1M) / 1_000_000 +
      (throughput.outputTokensPerMinute * m.outputPer1M) / 1_000_000;
    return perMinute * 60;
  };

  return (
    <div
      id="settings-modal-overlay"
      className="fixed inset-0 z-50 bg-neutral-950/40 backdrop-blur-xs flex items-center justify-center p-4 animate-in fade-in duration-100"
      onClick={onClose}
    >
      <div
        id="settings-modal"
        className="bg-white rounded-lg shadow-xl border border-neutral-200 w-full max-w-2xl flex flex-col max-h-[85vh] overflow-hidden animate-in zoom-in-95 duration-100"
        onClick={e => e.stopPropagation()}
      >
        {/* Header */}
        <div className="h-14 px-6 border-b border-neutral-200 flex items-center justify-between bg-neutral-50 shrink-0">
          <div className="flex items-center gap-2">
            <SettingsIcon className="w-4 h-4 text-neutral-700" />
            <h2 className="text-sm font-bold text-neutral-900">Settings</h2>
          </div>
          <button
            type="button"
            onClick={onClose}
            className="p-1 rounded-md text-neutral-400 hover:text-neutral-700 hover:bg-neutral-200/50"
            aria-label="Close settings"
          >
            <X className="w-4 h-4" />
          </button>
        </div>

        {/* Body */}
        <div className="p-6 overflow-y-auto flex flex-col gap-6">
          {/* Human rate */}
          <section>
            <div className="flex items-center gap-1.5 mb-1">
              <User className="w-3.5 h-3.5 text-neutral-500" />
              <h3 className="text-xs font-semibold text-neutral-900">People</h3>
            </div>
            <p className="text-[11px] text-neutral-500 mb-2">
              One blended rate applied to every person agent. Cost = planned hours × rate.
            </p>
            <div className="flex items-center gap-2">
              <select
                value={draft.currencySymbol}
                onChange={e => setDraft({ ...draft, currencySymbol: e.target.value })}
                className="text-xs px-2 py-2 border border-neutral-200 rounded-md bg-white focus:outline-none focus:border-neutral-900"
              >
                <option value="$">$</option>
                <option value="£">£</option>
                <option value="€">€</option>
              </select>
              <input
                id="human-hourly-rate-input"
                type="number"
                min={0}
                step={5}
                value={draft.humanHourlyRate}
                onChange={e => setDraft({ ...draft, humanHourlyRate: Number(e.target.value) || 0 })}
                className="w-32 text-xs px-3 py-2 border border-neutral-200 rounded-md focus:outline-none focus:border-neutral-900 font-mono"
              />
              <span className="text-xs text-neutral-500">per hour</span>
            </div>
          </section>

          {/* Model catalog */}
          <section>
            <div className="flex items-center justify-between mb-1">
              <h3 className="text-xs font-semibold text-neutral-900">Model rates</h3>
              <button
                type="button"
                onClick={addCustomModel}
                className="flex items-center gap-1 px-2 py-1 text-[11px] font-medium text-neutral-600 hover:text-neutral-900 hover:bg-neutral-100 rounded transition-colors"
              >
                <Plus className="w-3 h-3" />
                Add model
              </button>
            </div>
            <p className="text-[11px] text-neutral-500 mb-2">
              USD per 1M tokens, applied across every workspace. Assign a model to an AI
              agent when you add or edit it. Rates are editable — confirm against your
              provider's current pricing. The ≈ per hour column uses the active
              workspace's throughput assumptions.
            </p>

            <div className="border border-neutral-200 rounded-md overflow-hidden">
              <div className="grid grid-cols-[1fr_92px_92px_84px_32px] gap-2 px-3 py-1.5 bg-neutral-50 border-b border-neutral-200 text-[10px] font-semibold text-neutral-500 uppercase tracking-wider">
                <span>Model</span>
                <span className="text-right">Input /1M</span>
                <span className="text-right">Output /1M</span>
                <span className="text-right">≈ per hour</span>
                <span></span>
              </div>
              <div className="divide-y divide-neutral-100 max-h-56 overflow-y-auto">
                {draft.models.map(m => (
                  <div
                    key={m.id}
                    className="grid grid-cols-[1fr_92px_92px_84px_32px] gap-2 px-3 py-1.5 items-center text-xs"
                  >
                    {m.isCustom ? (
                      <input
                        type="text"
                        value={m.label}
                        onChange={e => updateModel(m.id, { label: e.target.value })}
                        className="text-xs px-1.5 py-1 border border-neutral-200 rounded focus:outline-none focus:border-neutral-900 min-w-0"
                      />
                    ) : (
                      <span className="truncate text-neutral-800 font-medium">{m.label}</span>
                    )}
                    <input
                      type="number"
                      min={0}
                      step={0.5}
                      value={m.inputPer1M}
                      onChange={e => updateModel(m.id, { inputPer1M: Number(e.target.value) || 0 })}
                      className="text-xs px-1.5 py-1 border border-neutral-200 rounded focus:outline-none focus:border-neutral-900 font-mono text-right"
                    />
                    <input
                      type="number"
                      min={0}
                      step={0.5}
                      value={m.outputPer1M}
                      onChange={e => updateModel(m.id, { outputPer1M: Number(e.target.value) || 0 })}
                      className="text-xs px-1.5 py-1 border border-neutral-200 rounded focus:outline-none focus:border-neutral-900 font-mono text-right"
                    />
                    <span className="font-mono text-[11px] text-neutral-500 text-right">
                      {formatMoney(modelHourlyRate(m), draft.currencySymbol)}
                    </span>
                    {m.isCustom ? (
                      <button
                        type="button"
                        onClick={() => removeModel(m.id)}
                        className="p-1 rounded text-neutral-400 hover:text-red-600 hover:bg-red-50 transition-colors justify-self-end"
                        title="Remove model"
                      >
                        <Trash2 className="w-3.5 h-3.5" />
                      </button>
                    ) : (
                      <span />
                    )}
                  </div>
                ))}
              </div>
            </div>
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
            id="save-settings-btn"
            type="button"
            onClick={() => {
              onSave(draft);
              onClose();
            }}
            className="px-4 py-1.5 bg-neutral-900 text-white rounded-md text-xs font-semibold hover:bg-neutral-800 transition-colors shadow-xs"
          >
            Save settings
          </button>
        </div>
      </div>
    </div>
  );
}
