// VAL-1 (US-VAL-1-02) — Pure normalisation, shared conceptually with the
// backend's functions/validate_field.xs (kept in sync by hand, same as
// the OBS-1 error catalog — see that file's header for why).
//
// Normalising is NOT validating: it cleans a value up (trims, collapses
// internal whitespace, strips control/zero-width characters) without
// ever rejecting it. Whether the *result* is acceptable is validate.ts's
// job.
const CONTROL_CHARS = /[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/g;
const ZERO_WIDTH = /[​‌‍﻿]/g;

export function stripControlAndZeroWidth(value: string): string {
  return value.replace(CONTROL_CHARS, '').replace(ZERO_WIDTH, '');
}

/** Trims the ends and collapses any run of internal whitespace to a single space. */
export function collapseSpaces(value: string): string {
  return value.replace(/\s+/g, ' ').trim();
}

export type NormalizeStep = 'trim' | 'collapseSpaces' | 'stripControl';

/**
 * Applies the given steps in order. "collapseSpaces" implies trim (it
 * always trims the ends), so listing both is redundant but harmless.
 */
export function normalizeText(value: string, steps: NormalizeStep[]): string {
  let result = value;
  for (const step of steps) {
    if (step === 'stripControl') result = stripControlAndZeroWidth(result);
    else if (step === 'collapseSpaces') result = collapseSpaces(result);
    else if (step === 'trim') result = result.trim();
  }
  return result;
}

/** A case-insensitive key for uniqueness checks: trim, collapse spaces, lowercase. */
export function toNameKey(value: string): string {
  return collapseSpaces(value).toLowerCase();
}
