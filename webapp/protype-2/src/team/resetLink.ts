// SAFE-1 story 03 — pure rules for the admin reset link (Manage users) and the set-password page.
//
// No email is sent (D-8): an admin makes a one-time link, sees it once and hands it over.
// Everything here is ALSO enforced on the server (`admin/user_reset_link`), which is the only
// authority. This file only lets the screen explain a refusal before the round trip.
import {passwordMeetsRules} from './teamModel';

interface ResetTarget {
  id: number;
  role: 'admin' | 'member';
  is_active: boolean;
  is_owner: boolean;
}

/**
 * Why this reset would be refused, as a catalog code, or null. Same order as the server:
 * not an admin → yourself → an AI → the owner → another admin (owner only) → switched off.
 */
export function resetBlockedBy(
  viewer: {id: number; role?: string | null} | null | undefined,
  viewerIsOwner: boolean,
  target: ResetTarget,
  targetIsAi: boolean,
): string | null {
  if (!viewer || viewer.role !== 'admin') return 'E-USR-001';
  if (viewer.id === target.id) return 'E-SAFE-009';
  if (targetIsAi) return 'E-SAFE-010';
  if (target.is_owner) return 'E-SAFE-007';
  if (target.role === 'admin' && !viewerIsOwner) return 'E-SAFE-006';
  if (!target.is_active) return 'E-SAFE-004';
  return null;
}

/**
 * The link the admin hands over. The token sits in the FRAGMENT (after #), which a browser
 * never sends to any server, so it cannot land in a server log or a referrer.
 */
export function buildResetLink(origin: string, token: string, email: string): string {
  return `${origin.replace(/\/+$/, '')}/set-password#token=${encodeURIComponent(token)}&email=${encodeURIComponent(email)}`;
}

/** Read the link back on the set-password page. Null when either part is missing. */
export function parseResetHash(hash: string): {token: string; email: string} | null {
  const params = new URLSearchParams(hash.replace(/^#/, ''));
  const token = (params.get('token') ?? '').trim();
  const email = (params.get('email') ?? '').trim();
  if (!token || !email) return null;
  return {token, email};
}

/** A sentence the person can act on, or null when the new password is fine. */
export function newPasswordProblem(password: string, confirm: string): string | null {
  if (password.length < 8) return 'Use at least 8 characters.';
  if (!passwordMeetsRules(password)) return 'Use at least one letter and one number.';
  if (password !== confirm) return "The two passwords don't match.";
  return null;
}
