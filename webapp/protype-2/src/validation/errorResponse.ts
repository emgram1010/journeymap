// VAL-1 (US-VAL-1-03) — The standard shape every rejection returns, and
// a lint that checks nothing else is leaking through it.
export interface StandardErrorResponse {
  code: string;
  field: string | null;
  message: string;
  reference: string | null;
}

export type StandardHttpStatus = 422 | 403 | 409;

export function buildErrorResponse(
  code: string,
  message: string,
  options: {field?: string; reference?: string} = {},
): StandardErrorResponse {
  return {
    code,
    field: options.field ?? null,
    message,
    reference: options.reference ?? null,
  };
}

// Patterns that mean raw technical detail leaked into a response that a
// user or a form will render directly. Deliberately literal, not
// clever — see the same approach in ops/errorCatalog.ts's jargon lint.
const LEAK_PATTERNS: RegExp[] = [
  /\bat \w+[.\w]*\(/, // a stack frame line
  /node_modules/,
  /\.xs:\d+/, // a XanoScript file:line reference
  /ERROR_FATAL|ERROR_CODE_\w+/, // a raw Xano error_type
  /\bSELECT\b.*\bFROM\b/i, // a leaked query
];

export interface ErrorResponseLintIssue {
  field: keyof StandardErrorResponse | 'shape';
  problem: string;
}

/**
 * Checks a response body against the standard shape and scans its
 * message for leaked technical detail. Returns an empty array when
 * clean.
 */
export function lintErrorResponse(body: unknown): ErrorResponseLintIssue[] {
  const issues: ErrorResponseLintIssue[] = [];

  if (body === null || typeof body !== 'object') {
    issues.push({field: 'shape', problem: 'response body is not an object'});
    return issues;
  }

  const record = body as Record<string, unknown>;

  if (typeof record.code !== 'string' || record.code === '') {
    issues.push({field: 'code', problem: 'missing or empty code'});
  }

  if (!('field' in record)) {
    issues.push({field: 'field', problem: 'missing field key (use null when not field-specific)'});
  } else if (record.field !== null && typeof record.field !== 'string') {
    issues.push({field: 'field', problem: 'field must be a string or null'});
  }

  if (typeof record.message !== 'string' || record.message === '') {
    issues.push({field: 'message', problem: 'missing or empty message'});
  } else {
    for (const pattern of LEAK_PATTERNS) {
      if (pattern.test(record.message)) {
        issues.push({field: 'message', problem: `message matches a leak pattern: ${pattern}`});
      }
    }
  }

  if (!('reference' in record)) {
    issues.push({field: 'reference', problem: 'missing reference key (use null when there is none)'});
  } else if (record.reference !== null && typeof record.reference !== 'string') {
    issues.push({field: 'reference', problem: 'reference must be a string or null'});
  }

  return issues;
}

/** Maps a VAL-1/OBS-1/GOV-1 error family to its standard HTTP status, for documentation and tests — not enforced by this module. */
export function statusForCode(code: string): StandardHttpStatus {
  if (code.startsWith('E-GOV-005')) return 409; // stale write
  if (code.startsWith('E-GOV-001') || code.startsWith('E-GOV-002') || code.startsWith('E-OBS-001')) return 403;
  return 422;
}
