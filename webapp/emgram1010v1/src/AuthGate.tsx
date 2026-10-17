// PLN-9 — This app has no router (confirmed: main.tsx renders one
// <App/>, no react-router-dom dependency at all), so this is a plain
// gate rather than a protected-route pattern: show a login form until
// there's a valid token, then render the real app. No signup here —
// planners are existing account members, not fresh signups.
import React, {useEffect, useState} from 'react';
import {RotateCcw, Eye, EyeOff} from 'lucide-react';
import {login, getMe, type AuthUser} from './lib/authApi';
import {XanoHttpError} from './lib/xanoHttpError';

interface AuthGateProps {
  children: (user: AuthUser) => React.ReactNode;
}

export default function AuthGate({children}: AuthGateProps) {
  const [user, setUser] = useState<AuthUser | null>(null);
  const [checkingSession, setCheckingSession] = useState(true);

  useEffect(() => {
    const stored = localStorage.getItem('authToken');
    if (!stored) {
      setCheckingSession(false);
      return;
    }
    getMe()
      .then(setUser)
      .catch(() => {
        localStorage.removeItem('authToken');
      })
      .finally(() => setCheckingSession(false));
  }, []);

  if (checkingSession) {
    return (
      <div className="min-h-screen bg-zinc-50 flex items-center justify-center">
        <div className="w-6 h-6 border-2 border-zinc-300 border-t-zinc-700 rounded-full animate-spin" />
      </div>
    );
  }

  if (!user) {
    return <LoginForm onSignedIn={setUser} />;
  }

  return <>{children(user)}</>;
}

function LoginForm({onSignedIn}: {onSignedIn: (user: AuthUser) => void}) {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [isLoading, setIsLoading] = useState(false);
  const [apiError, setApiError] = useState<string | null>(null);

  const canSubmit = !isLoading && !!email.trim() && !!password;

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!canSubmit) return;
    setIsLoading(true);
    setApiError(null);
    try {
      const {authToken} = await login(email.trim(), password);
      localStorage.setItem('authToken', authToken);
      const me = await getMe();
      onSignedIn(me);
    } catch (err) {
      // Never show a raw technical message (VAL-1) — this screen only
      // ever sees a 400/401/network failure, which are all "that
      // didn't work" from a planner's point of view.
      setApiError(err instanceof XanoHttpError && err.status === 401 ? 'Invalid email or password.' : 'Could not sign in. Check your connection and try again.');
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <div className="min-h-screen bg-zinc-50 flex items-center justify-center p-4">
      <div className="w-full max-w-sm">
        <div className="text-center mb-8">
          <div className="inline-flex items-center justify-center w-12 h-12 rounded-xl bg-zinc-900 text-white text-xl font-bold mb-3">E</div>
          <h1 className="text-xl font-bold text-zinc-900 tracking-tight">Emgram Planner</h1>
          <p className="text-sm text-zinc-500 mt-1">Sign in to your account</p>
        </div>

        <div className="bg-white rounded-2xl border border-zinc-200 shadow-sm p-8">
          {apiError && (
            <div className="mb-5 px-3 py-2.5 bg-rose-50 border border-rose-200 rounded-lg text-xs text-rose-700 font-medium">{apiError}</div>
          )}

          <form onSubmit={(e) => void handleSubmit(e)} noValidate className="space-y-5">
            <div>
              <label className="block text-xs font-semibold text-zinc-700 mb-1.5">Email</label>
              <input
                type="email"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                placeholder="you@example.com"
                autoComplete="email"
                className="w-full px-3 py-2.5 text-sm border border-zinc-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-zinc-200 transition"
              />
            </div>

            <div>
              <label className="block text-xs font-semibold text-zinc-700 mb-1.5">Password</label>
              <div className="relative">
                <input
                  type={showPassword ? 'text' : 'password'}
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  placeholder="••••••••"
                  autoComplete="current-password"
                  className="w-full px-3 py-2.5 pr-10 text-sm border border-zinc-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-zinc-200 transition"
                />
                <button
                  type="button"
                  onClick={() => setShowPassword((v) => !v)}
                  className="absolute right-3 top-1/2 -translate-y-1/2 text-zinc-400 hover:text-zinc-600"
                  tabIndex={-1}
                >
                  {showPassword ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
                </button>
              </div>
            </div>

            <button
              type="submit"
              disabled={!canSubmit}
              className="w-full flex items-center justify-center gap-2 py-2.5 px-4 bg-zinc-900 text-white text-sm font-semibold rounded-lg hover:bg-zinc-800 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
            >
              {isLoading ? (
                <>
                  <RotateCcw className="w-4 h-4 animate-spin" /> Signing in…
                </>
              ) : (
                'Sign in'
              )}
            </button>
          </form>
        </div>
      </div>
    </div>
  );
}
