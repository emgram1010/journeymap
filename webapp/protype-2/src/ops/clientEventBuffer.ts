// OBS-1 (US-OBS-1-04 dedup/rate cap; US-OBS-1-11 offline buffer) — Two
// small, independently-testable pieces:
//
// 1. ClientEventGate: a pre-send filter so a broken screen stuck in a
//    loop doesn't even try to send every failure. Mirrors the backend's
//    numbers (20/minute, a 5-second de-dup window per feature+step+code)
//    so the two layers agree, but this one runs first and for free.
// 2. OfflineEventBuffer: when the server can't be reached, failed
//    DIAGNOSTIC events (never user actions) are kept locally — at most
//    50, at most 7 days old — and sent once the connection returns.
import {redact} from './redact';

// ── 1. Dedup + rate cap ──────────────────────────────────────────────────

export interface ClientEventGateOptions {
  /** Max events allowed inside the rate window. Default 20 (matches the backend). */
  maxPerWindow?: number;
  /** Rate window length in ms. Default 60_000 (matches the backend). */
  windowMs?: number;
  /** How long an identical key is suppressed after being sent. Default 5_000 (matches the backend). */
  dedupMs?: number;
}

/**
 * Call `shouldSend(key)` before attempting to report an event. Returns
 * false when the same key was just sent (within dedupMs) or when the
 * rate cap for the window has been reached.
 */
export class ClientEventGate {
  private readonly maxPerWindow: number;
  private readonly windowMs: number;
  private readonly dedupMs: number;
  private readonly recentSendTimes: number[] = [];
  private readonly lastSentAtByKey = new Map<string, number>();

  constructor(options: ClientEventGateOptions = {}) {
    this.maxPerWindow = options.maxPerWindow ?? 20;
    this.windowMs = options.windowMs ?? 60_000;
    this.dedupMs = options.dedupMs ?? 5_000;
  }

  shouldSend(key: string, now: number = Date.now()): boolean {
    const lastSent = this.lastSentAtByKey.get(key);
    if (lastSent !== undefined && now - lastSent < this.dedupMs) {
      return false;
    }

    while (this.recentSendTimes.length > 0 && now - this.recentSendTimes[0] >= this.windowMs) {
      this.recentSendTimes.shift();
    }

    if (this.recentSendTimes.length >= this.maxPerWindow) {
      return false;
    }

    this.recentSendTimes.push(now);
    this.lastSentAtByKey.set(key, now);
    return true;
  }
}

// ── 2. Offline buffer ────────────────────────────────────────────────────

export interface EventBufferStorage {
  getItem(key: string): string | null;
  setItem(key: string, value: string): void;
}

/** In-memory fallback storage, used in tests and when localStorage is unavailable. */
export function createMemoryStorage(): EventBufferStorage {
  const store = new Map<string, string>();
  return {
    getItem: (key) => store.get(key) ?? null,
    setItem: (key, value) => store.set(key, value),
  };
}

/** Wraps localStorage, falling back to in-memory storage if it throws (private browsing, blocked storage, etc.). */
export function createBrowserStorage(): EventBufferStorage {
  try {
    const probeKey = '__ops_buffer_probe__';
    window.localStorage.setItem(probeKey, '1');
    window.localStorage.removeItem(probeKey);
    return {
      getItem: (key) => {
        try {
          return window.localStorage.getItem(key);
        } catch {
          return null;
        }
      },
      setItem: (key, value) => {
        try {
          window.localStorage.setItem(key, value);
        } catch {
          // Storage full or blocked — the event is dropped, which is
          // acceptable for best-effort diagnostics.
        }
      },
    };
  } catch {
    return createMemoryStorage();
  }
}

export interface BufferedOpsEvent {
  feature: string;
  step: string;
  outcome: 'failure';
  errorCode?: string | null;
  message?: string | null;
  metadata?: unknown;
  bufferedAt: number;
}

export interface OfflineEventBufferOptions {
  storageKey?: string;
  maxEntries?: number;
  maxAgeMs?: number;
}

const DEFAULT_MAX_ENTRIES = 50;
const DEFAULT_MAX_AGE_MS = 7 * 24 * 60 * 60 * 1000;

/**
 * Holds failed diagnostic events while offline. Never holds user
 * actions, and redacts `metadata` on the way in so nothing sensitive can
 * sit in localStorage.
 */
export class OfflineEventBuffer {
  private readonly storage: EventBufferStorage;
  private readonly storageKey: string;
  private readonly maxEntries: number;
  private readonly maxAgeMs: number;

  constructor(storage: EventBufferStorage = createMemoryStorage(), options: OfflineEventBufferOptions = {}) {
    this.storage = storage;
    this.storageKey = options.storageKey ?? 'ops_offline_event_buffer';
    this.maxEntries = options.maxEntries ?? DEFAULT_MAX_ENTRIES;
    this.maxAgeMs = options.maxAgeMs ?? DEFAULT_MAX_AGE_MS;
  }

  private readAll(now: number): BufferedOpsEvent[] {
    const raw = this.storage.getItem(this.storageKey);
    if (!raw) return [];
    let parsed: unknown;
    try {
      parsed = JSON.parse(raw);
    } catch {
      return [];
    }
    if (!Array.isArray(parsed)) return [];
    return (parsed as BufferedOpsEvent[]).filter((entry) => now - entry.bufferedAt <= this.maxAgeMs);
  }

  private writeAll(entries: BufferedOpsEvent[]): void {
    this.storage.setItem(this.storageKey, JSON.stringify(entries));
  }

  add(event: Omit<BufferedOpsEvent, 'bufferedAt'>, now: number = Date.now()): void {
    const current = this.readAll(now);
    const withRedactedMetadata: BufferedOpsEvent = {
      ...event,
      metadata: event.metadata !== undefined ? redact(event.metadata) : undefined,
      bufferedAt: now,
    };
    const next = [...current, withRedactedMetadata].slice(-this.maxEntries);
    this.writeAll(next);
  }

  /** Returns every non-expired buffered event and clears the buffer. Callers are responsible for sending them. */
  drain(now: number = Date.now()): BufferedOpsEvent[] {
    const entries = this.readAll(now);
    this.writeAll([]);
    return entries;
  }

  peek(now: number = Date.now()): BufferedOpsEvent[] {
    return this.readAll(now);
  }
}
