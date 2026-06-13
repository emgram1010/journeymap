import React, { useEffect, useState, useCallback } from 'react';
import { useNavigate } from 'react-router-dom';
import { ArrowLeft, Building2, Save, Check, AlertCircle, Loader2 } from 'lucide-react';
import { getAccountMe, updateAccountMe, type XanoAccount } from './xano';

type Field = keyof Pick<XanoAccount, 'name' | 'description' | 'location' | 'ai_context'>;

const FIELDS: { field: Field; label: string; placeholder: string; long: boolean; hint?: string }[] = [
  {
    field: 'name',
    label: 'Company Name',
    placeholder: 'e.g. Acme Corp',
    long: false,
  },
  {
    field: 'description',
    label: 'Company Description',
    placeholder: 'e.g. B2B SaaS platform for supply chain teams',
    long: true,
  },
  {
    field: 'location',
    label: 'Location',
    placeholder: 'e.g. San Francisco, CA',
    long: false,
  },
  {
    field: 'ai_context',
    label: 'What should the AI know about your company?',
    placeholder:
      "e.g. We're a B2B logistics platform. Our primary users are ops managers and fleet coordinators. " +
      "Internal teams are called Ops, Growth, and Platform. Our customers are mid-market shippers. " +
      "We use 'lanes' instead of 'stages' internally.",
    long: true,
    hint:
      'This context is injected into every AI conversation for your account. Be specific — industry, user types, internal terminology, and workflow norms all help.',
  },
];

export default function AccountSettings() {
  const navigate = useNavigate();
  const [account, setAccount] = useState<XanoAccount | null>(null);
  const [draft, setDraft] = useState<Partial<XanoAccount>>({});
  const [isLoading, setIsLoading] = useState(true);
  const [isSaving, setIsSaving] = useState(false);
  const [saved, setSaved] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const isAdmin = account?.role === 'admin';

  useEffect(() => {
    setIsLoading(true);
    getAccountMe()
      .then((data) => {
        setAccount(data);
        setDraft({ name: data.name ?? '', description: data.description ?? '', location: data.location ?? '', ai_context: data.ai_context ?? '' });
      })
      .catch(() => setError('Unable to load account settings.'))
      .finally(() => setIsLoading(false));
  }, []);

  const handleSave = useCallback(async () => {
    if (!isAdmin) return;
    setIsSaving(true);
    setError(null);
    setSaved(false);
    try {
      const updated = await updateAccountMe({ name: draft.name ?? '', description: draft.description ?? '', location: draft.location ?? '', ai_context: draft.ai_context ?? '' });
      setAccount(updated);
      setSaved(true);
      setTimeout(() => setSaved(false), 3000);
    } catch {
      setError('Failed to save. Please try again.');
    } finally {
      setIsSaving(false);
    }
  }, [draft, isAdmin]);

  return (
    <div className="min-h-screen bg-zinc-50 font-sans">
      {/* Header */}
      <header className="h-14 bg-white border-b border-zinc-200 flex items-center px-6 gap-4 sticky top-0 z-10">
        <button onClick={() => navigate(-1)} className="p-1.5 rounded hover:bg-zinc-100 text-zinc-500 transition">
          <ArrowLeft className="w-4 h-4" />
        </button>
        <div className="flex items-center gap-2">
          <Building2 className="w-4 h-4 text-zinc-400" />
          <span className="text-sm font-semibold text-zinc-900">Account Settings</span>
        </div>
      </header>

      <main className="max-w-2xl mx-auto px-6 py-10">
        {/* Error banner */}
        {error && (
          <div className="mb-6 flex items-center gap-2 px-4 py-3 rounded-lg bg-rose-50 border border-rose-200 text-rose-700 text-sm">
            <AlertCircle className="w-4 h-4 shrink-0" />
            {error}
          </div>
        )}

        {/* Loading skeleton */}
        {isLoading ? (
          <div className="space-y-4">
            {[80, 120, 60, 200].map((h, i) => (
              <div key={i} className="rounded-lg bg-zinc-200 animate-pulse" style={{ height: h }} />
            ))}
          </div>
        ) : (
          <div className="space-y-6">
            {!isAdmin && (
              <div className="px-4 py-3 rounded-lg bg-amber-50 border border-amber-200 text-amber-700 text-xs">
                You have read-only access. Only account admins can edit these settings.
              </div>
            )}

            {FIELDS.map(({ field, label, placeholder, long, hint }) => (
              <div key={field}>
                <label className="block text-xs font-bold text-zinc-500 uppercase tracking-wider mb-1.5">{label}</label>
                {hint && <p className="text-xs text-zinc-400 mb-2 leading-relaxed">{hint}</p>}
                {long ? (
                  <textarea
                    value={(draft[field] as string) ?? ''}
                    onChange={(e) => setDraft((d) => ({ ...d, [field]: e.target.value }))}
                    placeholder={placeholder}
                    disabled={!isAdmin}
                    rows={field === 'ai_context' ? 6 : 3}
                    className="w-full p-3 bg-white border border-zinc-200 rounded-lg text-sm text-zinc-800 placeholder:text-zinc-400 focus:outline-none focus:ring-2 focus:ring-zinc-300 resize-none disabled:opacity-50 disabled:bg-zinc-50"
                  />
                ) : (
                  <input
                    type="text"
                    value={(draft[field] as string) ?? ''}
                    onChange={(e) => setDraft((d) => ({ ...d, [field]: e.target.value }))}
                    placeholder={placeholder}
                    disabled={!isAdmin}
                    className="w-full p-3 bg-white border border-zinc-200 rounded-lg text-sm text-zinc-800 placeholder:text-zinc-400 focus:outline-none focus:ring-2 focus:ring-zinc-300 disabled:opacity-50 disabled:bg-zinc-50"
                  />
                )}
              </div>
            ))}

            {isAdmin && (
              <div className="flex items-center gap-3 pt-2">
                <button
                  onClick={handleSave}
                  disabled={isSaving}
                  className="inline-flex items-center gap-2 px-4 py-2 rounded-lg bg-zinc-900 text-white text-sm font-medium hover:bg-zinc-700 transition disabled:opacity-60"
                >
                  {isSaving ? <Loader2 className="w-4 h-4 animate-spin" /> : saved ? <Check className="w-4 h-4" /> : <Save className="w-4 h-4" />}
                  {isSaving ? 'Saving…' : saved ? 'Saved' : 'Save Settings'}
                </button>
                {saved && <span className="text-xs text-emerald-600">The AI will use this context from your next conversation.</span>}
              </div>
            )}
          </div>
        )}
      </main>
    </div>
  );
}
