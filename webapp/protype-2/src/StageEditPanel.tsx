import {useEffect, useRef, useState} from 'react';
import type {Stage, Lens, MatrixCell} from './types';

export type StageEditData = {
  label: string;
  primaryActorLens: string | null;
  stageGoal: string | null;
  timeDurationValue: number | null;
  timeDurationUnit: string | null;
  /** Plan vs Actual (TL-6) */
  plannedDuration: number | null;
  actualDuration: number | null;
};

type Props = {
  stage: Stage;
  lenses: Lens[];
  cells: MatrixCell[];
  onSave: (data: StageEditData) => void;
  onClose: () => void;
  isSaving: boolean;
};

export function StageEditPanel({stage, lenses, cells, onSave, onClose, isSaving}: Props) {
  const [label, setLabel] = useState(stage.label);
  const [primaryActorLens, setPrimaryActorLens] = useState(stage.primaryActorLens ?? '');
  const [stageGoal, setStageGoal] = useState(stage.stageGoal ?? '');

  // Find the primary actor's cell for this stage to pre-fill time duration
  const primaryCell = cells.find(
    (c) => c.stageId === stage.id && c.lensId === (stage.primaryActorLens ?? primaryActorLens),
  );
  const [timeDurationValue, setTimeDurationValue] = useState<string>(
    primaryCell?.timeDurationValue != null ? String(primaryCell.timeDurationValue) : '',
  );
  const [timeDurationUnit, setTimeDurationUnit] = useState<string>(
    primaryCell?.timeDurationUnit ?? 'minutes',
  );
  const [plannedDuration, setPlannedDuration] = useState<string>(
    primaryCell?.plannedDuration != null ? String(primaryCell.plannedDuration) : '',
  );
  const [actualDuration, setActualDuration] = useState<string>(
    primaryCell?.actualDuration != null ? String(primaryCell.actualDuration) : '',
  );

  const overlayRef = useRef<HTMLDivElement>(null);

  // Close on Escape
  useEffect(() => {
    const handleKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose();
    };
    window.addEventListener('keydown', handleKey);
    return () => window.removeEventListener('keydown', handleKey);
  }, [onClose]);

  // Close on click-outside
  const handleOverlayClick = (e: React.MouseEvent<HTMLDivElement>) => {
    if (e.target === overlayRef.current) onClose();
  };

  const handleSave = () => {
    if (!label.trim()) return;
    const parsedDuration = timeDurationValue.trim() !== '' ? parseFloat(timeDurationValue) : null;
    const parsedPlanned = plannedDuration.trim() !== '' ? parseFloat(plannedDuration) : null;
    const parsedActual = actualDuration.trim() !== '' ? parseFloat(actualDuration) : null;
    onSave({
      label: label.trim(),
      primaryActorLens: primaryActorLens || null,
      stageGoal: stageGoal.trim() || null,
      timeDurationValue: parsedDuration,
      timeDurationUnit: timeDurationUnit || null,
      plannedDuration: parsedPlanned,
      actualDuration: parsedActual,
    });
  };

  return (
    <div
      ref={overlayRef}
      onClick={handleOverlayClick}
      className="fixed inset-0 z-50 flex items-start justify-end bg-black/20"
    >
      <div className="w-[380px] h-full bg-white border-l border-zinc-200 shadow-xl flex flex-col">
        {/* Header */}
        <div className="flex items-center justify-between px-5 py-4 border-b border-zinc-200">
          <h2 className="text-sm font-semibold text-zinc-900">Edit Stage</h2>
          <button
            onClick={onClose}
            className="text-zinc-400 hover:text-zinc-700 text-lg leading-none"
            aria-label="Close"
          >
            ×
          </button>
        </div>

        {/* Body */}
        <div className="flex-1 overflow-y-auto px-5 py-5 space-y-5">
          {/* Stage Name */}
          <div>
            <label className="block text-[11px] font-semibold text-zinc-500 uppercase tracking-wider mb-1.5">
              Stage Name
            </label>
            <input
              type="text"
              value={label}
              onChange={(e) => setLabel(e.target.value)}
              className="w-full text-sm border border-zinc-300 rounded px-3 py-2 focus:outline-none focus:ring-2 focus:ring-indigo-400 text-zinc-900"
              placeholder="e.g. Receive Intake"
            />
          </div>

          {/* Primary Actor */}
          <div>
            <label className="block text-[11px] font-semibold text-zinc-500 uppercase tracking-wider mb-1.5">
              Primary Actor
            </label>
            <select
              value={primaryActorLens}
              onChange={(e) => setPrimaryActorLens(e.target.value)}
              className="w-full text-sm border border-zinc-300 rounded px-3 py-2 focus:outline-none focus:ring-2 focus:ring-indigo-400 text-zinc-900 bg-white"
            >
              <option value="">— None —</option>
              {lenses.map((l) => (
                <option key={l.id} value={l.key ?? l.id}>
                  {l.label}
                </option>
              ))}
            </select>
            <p className="mt-1 text-[10px] text-zinc-400">The actor accountable for this stage's outcome.</p>
          </div>

          {/* Stage Goal */}
          <div>
            <label className="block text-[11px] font-semibold text-zinc-500 uppercase tracking-wider mb-1.5">
              Stage Goal
            </label>
            <textarea
              value={stageGoal}
              onChange={(e) => setStageGoal(e.target.value)}
              rows={4}
              className="w-full text-sm border border-zinc-300 rounded px-3 py-2 focus:outline-none focus:ring-2 focus:ring-indigo-400 text-zinc-900 resize-none"
              placeholder="What must be TRUE when this stage is done?"
            />
            <p className="mt-1 text-[10px] text-zinc-400">One sentence exit condition — the definition of done for this stage.</p>
          </div>

          {/* Time Duration — L3 leakage math input */}
          <div>
            <label className="block text-[11px] font-semibold text-zinc-500 uppercase tracking-wider mb-1.5">
              Time on Task <span className="text-zinc-400 font-normal normal-case">(leakage math)</span>
            </label>
            {!primaryActorLens ? (
              <p className="text-[11px] text-amber-600 bg-amber-50 border border-amber-200 rounded px-3 py-2">
                Set a Primary Actor above to enable time tracking.
              </p>
            ) : (
              <>
                <div className="flex gap-2">
                  <input
                    type="number"
                    min="0"
                    step="0.1"
                    value={timeDurationValue}
                    onChange={(e) => setTimeDurationValue(e.target.value)}
                    placeholder="e.g. 15"
                    className="w-24 text-sm border border-zinc-300 rounded px-3 py-2 focus:outline-none focus:ring-2 focus:ring-indigo-400 text-zinc-900"
                  />
                  <select
                    value={timeDurationUnit}
                    onChange={(e) => setTimeDurationUnit(e.target.value)}
                    className="flex-1 text-sm border border-zinc-300 rounded px-3 py-2 focus:outline-none focus:ring-2 focus:ring-indigo-400 text-zinc-900 bg-white"
                  >
                    <option value="minutes">minutes</option>
                    <option value="hours">hours</option>
                    <option value="days">days</option>
                    <option value="weeks">weeks</option>
                  </select>
                </div>
                <p className="mt-1 text-[10px] text-zinc-400">Saved to the primary actor's cell for this stage.</p>

                {/* Plan vs Actual (TL-6) */}
                <div className="mt-3 grid grid-cols-2 gap-2">
                  <div>
                    <label className="text-[10px] font-bold text-zinc-400 uppercase tracking-wider block mb-1">Planned</label>
                    <input
                      type="number"
                      min="0"
                      step="0.1"
                      value={plannedDuration}
                      onChange={(e) => setPlannedDuration(e.target.value)}
                      placeholder="Blueprint"
                      className="w-full text-sm border border-zinc-300 rounded px-3 py-2 focus:outline-none focus:ring-2 focus:ring-indigo-400 text-zinc-900"
                    />
                  </div>
                  <div>
                    <label className="text-[10px] font-bold text-zinc-400 uppercase tracking-wider block mb-1">Actual</label>
                    <input
                      type="number"
                      min="0"
                      step="0.1"
                      value={actualDuration}
                      onChange={(e) => setActualDuration(e.target.value)}
                      placeholder="Real-world"
                      className="w-full text-sm border border-zinc-300 rounded px-3 py-2 focus:outline-none focus:ring-2 focus:ring-indigo-400 text-zinc-900"
                    />
                  </div>
                </div>
                <p className="mt-1 text-[10px] text-zinc-400">Plan vs actual in same unit as duration above.</p>
              </>
            )}
          </div>
        </div>

        {/* Footer */}
        <div className="px-5 py-4 border-t border-zinc-200 flex items-center justify-end gap-3">
          <button
            onClick={onClose}
            className="px-4 py-1.5 text-sm text-zinc-600 hover:text-zinc-900 transition-colors"
          >
            Cancel
          </button>
          <button
            onClick={handleSave}
            disabled={isSaving || !label.trim()}
            className="px-4 py-1.5 bg-indigo-600 text-white text-sm font-medium rounded hover:bg-indigo-700 disabled:opacity-40 transition-colors"
          >
            {isSaving ? 'Saving…' : 'Save'}
          </button>
        </div>
      </div>
    </div>
  );
}
