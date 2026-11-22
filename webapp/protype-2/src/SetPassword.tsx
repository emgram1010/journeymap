import React, {useEffect, useState} from 'react';
import {Link, useNavigate} from 'react-router-dom';
import {Eye, EyeOff} from 'lucide-react';
import {setPasswordWithResetLink, XanoHttpError} from './xano';
import {newPasswordProblem, parseResetHash} from './team/resetLink';

/**
 * SAFE-1 story 03 — where a one-time reset link lands.
 *
 * An admin made the link on Manage users and handed it over (no email is sent, D-8). This page
 * does ONE thing: set a new password. It keeps no session; the person signs in afterwards with
 * the new password. The token is read from the link's fragment (after #), which the browser
 * never sends to a server, and it is wiped from the address bar as soon as it has been read.
 *
 * A link that is used, replaced, cancelled or past its hour is refused by the server; whatever
 * the reason, the person sees the same next step: ask an admin for a new one.
 */
export default function SetPassword() {
  const navigate = useNavigate();
  // Read on first render; scrub the address bar AFTER mount so the token is not left in history.
  // (Scrubbing during render would lose it when React renders twice in development.)
  const [link] = useState(() => parseResetHash(window.location.hash));
  useEffect(() => {
    if (window.location.hash) window.history.replaceState(null, '', window.location.pathname);
  }, []);

  const [password, setPassword] = useState('');
  const [confirm, setConfirm] = useState('');
  const [show, setShow] = useState(false);
  const [touched, setTouched] = useState(false);
  const [isSaving, setIsSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const problem = newPasswordProblem(password, confirm);

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    setTouched(true);
    if (!link || problem) return;
    setIsSaving(true);
    setError(null);
    try {
      await setPasswordWithResetLink(link.token, link.email, password);
      navigate('/login', {replace: true, state: {notice: 'Your new password is set. Sign in with it.'}});
    } catch (err) {
      // The typing stays (house rule). A dead link gets one plain next step, whatever killed it.
      const reached = err instanceof XanoHttpError;
      setError(
        reached
          ? 'This link has expired or was already used. Ask an admin for a new one.'
          : "We couldn't reach Emgram. Check your connection and try again.",
      );
    } finally {
      setIsSaving(false);
    }
  };

  return (
    <div className="min-h-screen bg-zinc-50 flex items-center justify-center p-4">
      <div className="w-full max-w-sm">
        <div className="text-center mb-8">
          <div className="inline-flex items-center justify-center w-12 h-12 rounded-xl bg-zinc-900 text-white text-xl font-bold mb-3">
            E
          </div>
          <h1 className="text-xl font-bold text-zinc-900 tracking-tight">Emgram</h1>
          <p className="text-sm text-zinc-500 mt-1">Set a new password</p>
        </div>

        <div className="bg-white rounded-2xl border border-zinc-200 shadow-sm p-8">
          {!link ? (
            <div role="alert" className="text-sm text-zinc-700">
              <p className="font-medium text-zinc-900">This link isn&apos;t complete.</p>
              <p className="mt-2">Ask an admin for a new reset link, and open it exactly as they gave it to you.</p>
              <Link to="/login" className="mt-4 inline-block text-sm font-medium text-zinc-900 underline">
                Back to sign in
              </Link>
            </div>
          ) : (
            <form onSubmit={submit} noValidate>
              <p className="mb-5 text-xs text-zinc-500">
                For <span className="font-medium text-zinc-700">{link.email}</span>. This link works once.
              </p>

              {error && (
                <div role="alert" className="mb-5 px-3 py-2.5 bg-rose-50 border border-rose-200 rounded-lg text-xs text-rose-700 font-medium">
                  {error}
                </div>
              )}

              <label htmlFor="new-password" className="block text-xs font-medium text-zinc-700 mb-1">
                New password
              </label>
              <div className="relative mb-4">
                <input
                  id="new-password"
                  type={show ? 'text' : 'password'}
                  autoComplete="new-password"
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  className="w-full rounded-lg border border-zinc-300 px-3 py-2 pr-10 text-sm"
                />
                <button
                  type="button"
                  aria-label={show ? 'Hide password' : 'Show password'}
                  onClick={() => setShow(!show)}
                  className="absolute right-2 top-1/2 -translate-y-1/2 p-1 text-zinc-400 hover:text-zinc-600"
                >
                  {show ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
                </button>
              </div>

              <label htmlFor="confirm-password" className="block text-xs font-medium text-zinc-700 mb-1">
                Type it again
              </label>
              <input
                id="confirm-password"
                type={show ? 'text' : 'password'}
                autoComplete="new-password"
                value={confirm}
                onChange={(e) => setConfirm(e.target.value)}
                className="w-full rounded-lg border border-zinc-300 px-3 py-2 text-sm"
              />

              <p className={`mt-2 text-xs ${touched && problem ? 'text-rose-600' : 'text-zinc-500'}`}>
                {touched && problem ? problem : 'At least 8 characters, with a letter and a number.'}
              </p>

              <button
                type="submit"
                disabled={isSaving}
                className="mt-5 w-full rounded-lg bg-zinc-900 px-3 py-2.5 text-sm font-medium text-white hover:bg-zinc-800 disabled:opacity-50"
              >
                {isSaving ? 'Saving…' : 'Set password'}
              </button>
            </form>
          )}
        </div>
      </div>
    </div>
  );
}
