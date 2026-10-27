import React, { createContext, useContext, useEffect, useState, useCallback } from 'react';
import { loginUser, signupUser, getAuthMe, XanoHttpError, type XanoUser } from './xano';
import { resetModuleGrantsCache } from './team/moduleGrantsCache';

interface AuthState {
  user: XanoUser | null;
  token: string | null;
  /** True while the initial localStorage token is being validated on mount. */
  isLoading: boolean;
}

interface AuthContextValue extends AuthState {
  login: (email: string, password: string) => Promise<void>;
  signup: (name: string, email: string, password: string) => Promise<void>;
  logout: () => void;
}

const AuthContext = createContext<AuthContextValue | null>(null);

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const [state, setState] = useState<AuthState>({ user: null, token: null, isLoading: true });

  useEffect(() => {
    const stored = localStorage.getItem('authToken');
    if (!stored) {
      setState({ user: null, token: null, isLoading: false });
      return;
    }
    // Validate the stored token via GET /auth/me.
    //
    // O14 (2026-10-17) — THE TOKEN IS ONLY DESTROYED FOR AN ACTUAL
    // AUTH FAILURE. This used to clear it on ANY rejection, which
    // meant a perfectly good session was thrown away by anything that
    // made this one request fail: a flaky network, a 500, or — the way
    // it was found — a request ABORTED because the user navigated
    // somewhere else before it came back. Playwright reproduced it
    // every time: open a page, navigate again immediately, and the
    // in-flight check's abort logged the session out mid-navigation.
    // A person clicking quickly on a slow connection hits the same
    // thing, and the only symptom is being bounced to the sign-in
    // page for no visible reason.
    //
    // 401/403 means the token really is no good — clear it. Anything
    // else means WE could not find out, which is not the same answer:
    // the token stays, so the next load (or the next online moment)
    // signs them straight back in.
    getAuthMe()
      .then((user) => setState({ user, token: stored, isLoading: false }))
      .catch((err: unknown) => {
        const status = err instanceof XanoHttpError ? err.status : 0;
        const tokenIsRejected = status === 401 || status === 403;
        if (tokenIsRejected) {
          localStorage.removeItem('authToken');
          localStorage.removeItem('userId');
        }
        setState({ user: null, token: null, isLoading: false });
      });
  }, []);

  const login = useCallback(async (email: string, password: string) => {
    const { authToken, userId } = await loginUser(email, password);
    localStorage.setItem('authToken', authToken);
    localStorage.setItem('userId', String(userId));
    const user = await getAuthMe();
    setState({ user, token: authToken, isLoading: false });
  }, []);

  const signup = useCallback(async (name: string, email: string, password: string) => {
    const { authToken, userId } = await signupUser(name, email, password);
    localStorage.setItem('authToken', authToken);
    localStorage.setItem('userId', String(userId));
    const user = await getAuthMe();
    setState({ user, token: authToken, isLoading: false });
  }, []);

  const logout = useCallback(() => {
    localStorage.removeItem('authToken');
    localStorage.removeItem('userId');
    // USR-2: module grants are cached per user id for the life of the tab, so
    // one page load does not fetch them five times. Signing out has to drop
    // that cache, or signing back in serves whatever was true before — which
    // matters most in the case somebody signs out BECAUSE their access
    // changed.
    resetModuleGrantsCache();
    setState({ user: null, token: null, isLoading: false });
  }, []);

  return (
    <AuthContext.Provider value={{ ...state, login, signup, logout }}>
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth(): AuthContextValue {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error('useAuth must be used inside <AuthProvider>');
  return ctx;
}
