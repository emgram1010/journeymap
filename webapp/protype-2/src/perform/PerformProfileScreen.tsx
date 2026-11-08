// EXEC-1 (US-EXEC-1-09) — the Profile tab: name, email, sign out.
// Uses the app's existing `useAuth()`/`logout()` — no separate
// sign-out flow for the perform app.
import {LogOut} from 'lucide-react';
import {useAuth} from '../AuthContext';

export default function PerformProfileScreen() {
  const {user, logout} = useAuth();

  return (
    <div className="min-h-screen bg-zinc-50 pb-20">
      <header className="sticky top-0 bg-white border-b border-zinc-200 px-4 py-3">
        <h1 className="text-base font-semibold text-zinc-900">Profile</h1>
      </header>

      <main className="px-4 py-4">
        <div className="rounded-xl border border-zinc-200 bg-white p-4">
          <p className="text-sm font-medium text-zinc-900">{user?.name ?? 'Unknown'}</p>
          {user?.email && <p className="mt-0.5 text-sm text-zinc-500">{user.email}</p>}
        </div>

        <button
          type="button"
          onClick={logout}
          className="mt-4 flex min-h-[44px] w-full items-center justify-center gap-2 rounded-lg border border-zinc-300 bg-white px-4 text-sm font-medium text-zinc-700"
        >
          <LogOut className="h-4 w-4" aria-hidden="true" />
          Sign out
        </button>
      </main>
    </div>
  );
}
