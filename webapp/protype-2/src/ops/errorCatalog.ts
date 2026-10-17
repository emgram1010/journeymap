// OBS-1 (US-OBS-1-03) — One source of truth for error text: every code
// used anywhere (frontend or backend) must have an entry here with no
// jargon and no raw technical text in `user_message`.
//
// IMPORTANT: a backend copy of this exact content lives in
// functions/ops/error_catalog.xs, kept in sync by hand (see that file's
// header comment for why).
import catalogJson from './errorCatalog.json';

export type CatalogOwner = 'user' | 'product_manager' | 'engineer';
export type CatalogSeverity = 'info' | 'warn' | 'error';

export interface CatalogEntry {
  code: string;
  feature: string;
  user_message: string;
  what_happened: string;
  likely_cause: string;
  owner: CatalogOwner;
  severity: CatalogSeverity;
  fix_hint: string;
}

export type ErrorCatalog = Record<string, CatalogEntry>;

export const errorCatalog: ErrorCatalog = catalogJson as ErrorCatalog;

const REQUIRED_FIELDS: (keyof CatalogEntry)[] = [
  'code',
  'feature',
  'user_message',
  'what_happened',
  'likely_cause',
  'owner',
  'severity',
  'fix_hint',
];

const VALID_OWNERS: CatalogOwner[] = ['user', 'product_manager', 'engineer'];
const VALID_SEVERITIES: CatalogSeverity[] = ['info', 'warn', 'error'];

// Words that signal raw technical/stack-trace text leaking into a
// user-facing message. Kept deliberately small and literal rather than
// clever, so the lint stays predictable.
const JARGON_PATTERNS: RegExp[] = [
  /\bstack trace\b/i,
  /\bnull pointer\b/i,
  /\bundefined is not a function\b/i,
  /\bat \w+\.\w+\(/, // "at Foo.bar(" — a stack frame line
  /\bE-[A-Z]+-\d{3}\b/, // a raw catalog code inside the friendly message
  /\b(TypeError|ReferenceError|SyntaxError|RangeError)\b/,
];

export interface CatalogValidationIssue {
  code: string;
  problem: string;
}

/**
 * Validates the whole catalog: every entry has every required field, a
 * valid owner, a valid severity, and a user_message with no jargon or a
 * raw code embedded in it. Returns an empty array when the catalog is
 * clean.
 */
export function validateCatalog(catalog: ErrorCatalog): CatalogValidationIssue[] {
  const issues: CatalogValidationIssue[] = [];

  for (const [key, entry] of Object.entries(catalog)) {
    if (!entry || typeof entry !== 'object') {
      issues.push({code: key, problem: 'entry is not an object'});
      continue;
    }

    if (entry.code !== key) {
      issues.push({code: key, problem: `entry.code ("${entry.code}") does not match its catalog key ("${key}")`});
    }

    for (const field of REQUIRED_FIELDS) {
      const value = entry[field];
      if (value === undefined || value === null || value === '') {
        issues.push({code: key, problem: `missing required field "${field}"`});
      }
    }

    if (entry.owner !== undefined && !VALID_OWNERS.includes(entry.owner)) {
      issues.push({code: key, problem: `owner "${entry.owner}" is not one of ${VALID_OWNERS.join(', ')}`});
    }

    if (entry.severity !== undefined && !VALID_SEVERITIES.includes(entry.severity)) {
      issues.push({code: key, problem: `severity "${entry.severity}" is not one of ${VALID_SEVERITIES.join(', ')}`});
    }

    if (typeof entry.user_message === 'string') {
      for (const pattern of JARGON_PATTERNS) {
        if (pattern.test(entry.user_message)) {
          issues.push({code: key, problem: `user_message contains jargon/raw text matching ${pattern}`});
        }
      }
    }
  }

  return issues;
}

/** Looks up one entry, or undefined when the code is unknown. */
export function getCatalogEntry(code: string | null | undefined): CatalogEntry | undefined {
  if (!code) return undefined;
  return errorCatalog[code];
}

/**
 * Every `E-XXX-NNN`-shaped code found in the given source text must
 * exist in the catalog. Used by the "scan source for codes" test
 * (UT-OBS-1-02) — see errorCatalog.test.ts for how source files are
 * collected.
 */
export function findUncatalogedCodes(sourceText: string, catalog: ErrorCatalog): string[] {
  const pattern = /\bE-[A-Z]+-\d{3}\b/g;
  const found = new Set<string>();
  for (const match of sourceText.matchAll(pattern)) {
    found.add(match[0]);
  }
  return [...found].filter((code) => !(code in catalog));
}
