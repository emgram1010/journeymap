import React, { createContext, useContext, useEffect, useState, useCallback } from 'react';
import { loginUser, signupUser, getAuthMe, type XanoUser } from './xano';

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
    // Validate the stored token via GET /auth/me
    getAuthMe()
      .then((user) => setState({ user, token: stored, isLoading: false }))
      .catch(() => {
        localStorage.removeItem('authToken');
        localStorage.removeItem('userId');
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
