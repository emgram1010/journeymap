// PLN-9 — This app's own login. It has never had one (confirmed: no
// auth/login/localStorage reference anywhere in the original source)
// because it never called anything real. A SEPARATE ORIGIN from
// protype-2 means it cannot borrow that app's session — see
// xanoHttpError.ts's note on this. Targets the SAME Authentication
// API group protype-2 uses (`RPonubWS`), so one account logs into
// both apps, just as two separate sign-ins.
import {XanoHttpError} from './xanoHttpError';
import {CORRELATION_HEADER, newCorrelationId} from './correlationId';

const DEFAULT_AUTH_BASE_URL = 'https://xdjc-i7zz-jhm2.n7e.xano.io/api:RPonubWS';

function trimTrailingSlash(value: string): string {
  return value.endsWith('/') ? value.slice(0, -1) : value;
}

export function getAuthBaseUrl(): string {
  const configured = import.meta.env.VITE_XANO_AUTH_BASE_URL?.trim();
  return trimTrailingSlash(configured || DEFAULT_AUTH_BASE_URL);
}

export interface AuthUser {
  id: number;
  name: string;
  email: string;
  account_id: number | null;
  role: string | null;
  is_platform_admin?: boolean | null;
}

async function authRequest<T>(path: string, body?: Record<string, unknown>): Promise<T> {
  const correlationId = newCorrelationId();
  const token = typeof localStorage !== 'undefined' ? localStorage.getItem('authToken') : null;
  const headers: Record<string, string> = {Accept: 'application/json', [CORRELATION_HEADER]: correlationId};
  if (token) headers['Authorization'] = `Bearer ${token}`;
  if (body) headers['Content-Type'] = 'application/json';

  const response = await fetch(`${getAuthBaseUrl()}${path}`, {
    method: body ? 'POST' : 'GET',
    headers,
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await response.text();
  if (!response.ok) {
    throw new XanoHttpError(response.status, `Auth ${path} failed (${response.status}): ${text || response.statusText}`, correlationId);
  }
  return text ? (JSON.parse(text) as T) : (undefined as T);
}

export const login = (email: string, password: string) => authRequest<{authToken: string; user_id: number}>('/auth/login', {email, password});

export const getMe = () => authRequest<AuthUser>('/auth/me');
