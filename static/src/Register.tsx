import React, { useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { Eye, EyeOff, RotateCcw, Check } from 'lucide-react';
import { useAuth } from './AuthContext';

function passwordStrength(pw: string): 'weak' | 'fair' | 'strong' {
  if (pw.length < 8) return 'weak';
  const hasUpper = /[A-Z]/.test(pw);
  const hasLower = /[a-z]/.test(pw);
  const hasDigit = /[0-9]/.test(pw);
  const hasSpecial = /[^A-Za-z0-9]/.test(pw);
  const score = [hasUpper, hasLower, hasDigit, hasSpecial].filter(Boolean).length;
  return score >= 3 ? 'strong' : 'fair';
}

const strengthColor = { weak: 'bg-rose-400', fair: 'bg-amber-400', strong: 'bg-emerald-500' };
const strengthLabel = { weak: 'Weak', fair: 'Fair', strong: 'Strong' };
const strengthWidth = { weak: 'w-1/3', fair: 'w-2/3', strong: 'w-full' };

export default function Register() {
  const { signup } = useAuth();
  const navigate = useNavigate();

  const [name, setName] = useState('');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [confirm, setConfirm] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [touched, setTouch] = useState({ name: false, email: false, password: false, confirm: false });
  const [isLoading, setIsLoading] = useState(false);
  const [apiError, setApiError] = useState<string | null>(null);

  const touch = (field: keyof typeof touched) => setTouch((t) => ({ ...t, [field]: true }));

  const nameError = touched.name && !name.trim() ? 'Name is required.' : null;
  const emailError = touched.email && !email.trim() ? 'Email is required.' : null;
  const passwordError = touched.password && password.length < 8 ? 'Password must be at least 8 characters.' : null;
  const confirmError = touched.confirm && confirm !== password ? 'Passwords do not match.' : null;
  const strength = password.length > 0 ? passwordStrength(password) : null;
  const passwordsMatch = confirm.length > 0 && confirm === password;
  const canSubmit = !isLoading && !!name.trim() && !!email.trim() && password.length >= 8 && confirm === password;

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setTouch({ name: true, email: true, password: true, confirm: true });
    if (!name.trim() || !email.trim() || password.length < 8 || confirm !== password) return;

    setIsLoading(true);
    setApiError(null);
    try {
      await signup(name.trim(), email.trim(), password);
      navigate('/dashboard', { replace: true });
    } catch (err) {
      const msg = err instanceof Error ? err.message : '';
      setApiError(msg.toLowerCase().includes('already') ? 'An account with this email already exists.' : 'Something went wrong. Please try again.');
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <div className="min-h-screen bg-zinc-50 flex items-center justify-center p-4">
      <div className="w-full max-w-sm">
        {/* Brand */}
        <div className="text-center mb-8">
          <div className="inline-flex items-center justify-center w-12 h-12 rounded-xl bg-zinc-900 text-white text-xl font-bold mb-3">E</div>
          <h1 className="text-xl font-bold text-zinc-900 tracking-tight">Emgram</h1>
          <p className="text-sm text-zinc-500 mt-1">Create your account</p>
        </div>

        {/* Card */}
        <div className="bg-white rounded-2xl border border-zinc-200 shadow-sm p-8">
          {apiError && (
            <div className="mb-5 px-3 py-2.5 bg-rose-50 border border-rose-200 rounded-lg text-xs text-rose-700 font-medium">{apiError}</div>
          )}

          <form onSubmit={(e) => void handleSubmit(e)} noValidate className="space-y-5">
            <div>
              <label className="block text-xs font-semibold text-zinc-700 mb-1.5">Full name</label>
              <input type="text" value={name} onChange={(e) => setName(e.target.value)} onBlur={() => touch('name')}
                placeholder="Jane Smith" autoComplete="name"
                className={`w-full px-3 py-2.5 text-sm border rounded-lg focus:outline-none focus:ring-2 transition ${nameError ? 'border-rose-300 focus:ring-rose-200' : 'border-zinc-200 focus:ring-zinc-200'}`} />
              {nameError && <p className="mt-1 text-[11px] text-rose-600">{nameError}</p>}
            </div>

            <div>
              <label className="block text-xs font-semibold text-zinc-700 mb-1.5">Email</label>
              <input type="email" value={email} onChange={(e) => setEmail(e.target.value)} onBlur={() => touch('email')}
                placeholder="you@example.com" autoComplete="email"
                className={`w-full px-3 py-2.5 text-sm border rounded-lg focus:outline-none focus:ring-2 transition ${emailError ? 'border-rose-300 focus:ring-rose-200' : 'border-zinc-200 focus:ring-zinc-200'}`} />
              {emailError && <p className="mt-1 text-[11px] text-rose-600">{emailError}</p>}
            </div>

            <div>
              <label className="block text-xs font-semibold text-zinc-700 mb-1.5">Password</label>
              <div className="relative">
                <input type={showPassword ? 'text' : 'password'} value={password} onChange={(e) => setPassword(e.target.value)} onBlur={() => touch('password')}
                  placeholder="••••••••" autoComplete="new-password"
                  className={`w-full px-3 py-2.5 pr-10 text-sm border rounded-lg focus:outline-none focus:ring-2 transition ${passwordError ? 'border-rose-300 focus:ring-rose-200' : 'border-zinc-200 focus:ring-zinc-200'}`} />
                <button type="button" onClick={() => setShowPassword((v) => !v)} tabIndex={-1} className="absolute right-3 top-1/2 -translate-y-1/2 text-zinc-400 hover:text-zinc-600">
                  {showPassword ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
                </button>
              </div>
              {strength && (
                <div className="mt-2">
                  <div className="h-1 bg-zinc-100 rounded-full overflow-hidden">
                    <div className={`h-full rounded-full transition-all ${strengthColor[strength]} ${strengthWidth[strength]}`} />
                  </div>
                  <p className={`text-[11px] mt-1 font-medium ${strength === 'strong' ? 'text-emerald-600' : strength === 'fair' ? 'text-amber-600' : 'text-rose-500'}`}>{strengthLabel[strength]}</p>
                </div>
              )}
              {passwordError && <p className="mt-1 text-[11px] text-rose-600">{passwordError}</p>}
            </div>

            <div>
              <label className="block text-xs font-semibold text-zinc-700 mb-1.5">Confirm password</label>
              <div className="relative">
                <input type="password" value={confirm} onChange={(e) => setConfirm(e.target.value)} onBlur={() => touch('confirm')}
                  placeholder="••••••••" autoComplete="new-password"
                  className={`w-full px-3 py-2.5 pr-10 text-sm border rounded-lg focus:outline-none focus:ring-2 transition ${confirmError ? 'border-rose-300 focus:ring-rose-200' : 'border-zinc-200 focus:ring-zinc-200'}`} />
                {passwordsMatch && (
                  <Check className="absolute right-3 top-1/2 -translate-y-1/2 w-4 h-4 text-emerald-500" />
                )}
              </div>
              {confirmError && <p className="mt-1 text-[11px] text-rose-600">{confirmError}</p>}
            </div>

            <button type="submit" disabled={!canSubmit}
              className="w-full flex items-center justify-center gap-2 py-2.5 px-4 bg-zinc-900 text-white text-sm font-semibold rounded-lg hover:bg-zinc-800 disabled:opacity-50 disabled:cursor-not-allowed transition-colors">
              {isLoading ? <><RotateCcw className="w-4 h-4 animate-spin" /> Creating account…</> : 'Create account'}
            </button>
          </form>
        </div>

        <p className="text-center text-xs text-zinc-500 mt-5">
          Already have an account?{' '}
          <Link to="/login" className="text-zinc-900 font-semibold hover:underline">Sign in</Link>
        </p>
      </div>
    </div>
  );
}
