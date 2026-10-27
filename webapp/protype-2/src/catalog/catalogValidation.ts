// CAT-1 (US-CAT-1-01/02/03) — Validation for the item-type and method
// catalogs. Pure functions, no network, no Xano — the backend twin is
// functions/catalog/validate_key_and_label.xs, kept in sync by hand (same
// pattern as OBS-1's error catalog and TIME-1's duration model: no shared
// build step between the Vite frontend and the Xano backend in this repo).
//
// TWO DIFFERENT THINGS, DO NOT CONFUSE THEM:
//   - `normaliseKey` is a SUGGESTION generator (slugify), used by the UI
//     to turn a typed label into a key suggestion the user can still edit
//     (US-CAT-1-04: "key auto-suggested from label, editable").
//   - `validateKey` checks the value that will actually be STORED, which
//     only goes through Xano's `filters=trim|lower` — trim and lowercase,
//     nothing else. A key typed by hand as "Chair Resin" (not run through
//     the suggestion) is stored as "chair resin" (space kept) and MUST be
//     rejected here; the column filter alone does not enforce the
//     hyphen-only pattern.
import type {CatalogUnit} from './catalogTypes';

export type CatalogValidationResult = {valid: true} | {valid: false; code: string};

const KEY_PATTERN = /^[a-z0-9][a-z0-9-]*$/;
const KEY_MIN_LENGTH = 2;
const KEY_MAX_LENGTH = 40;
const LABEL_MAX_LENGTH = 80;
// Same shape CLAUDE.md confirmed live for the backend's regex_matches HTML
// check ("/<[a-zA-Z][^>]*>/") — ported to a JS RegExp for the frontend twin.
const HTML_TAG_PATTERN = /<[a-zA-Z][^>]*>/;
const VALID_UNITS: CatalogUnit[] = ['each', 'set', 'pair'];

/**
 * UT-CAT-1-01 — Slugifies free text into a key suggestion: trim, lowercase,
 * collapse any run of non [a-z0-9] characters into a single hyphen, and
 * strip leading/trailing hyphens. A pure suggestion — the caller may still
 * edit the result, and the result must still pass `validateKey` before it
 * is stored.
 */
export function normaliseKey(input: string): string {
  return input
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
}

/**
 * The value that will actually be stored, mirroring the table's own
 * `filters=trim|lower` exactly (trim + lowercase, nothing else). This is
 * NOT a slugify — it's what the column filter does to whatever is typed.
 */
export function storedKey(raw: string): string {
  return raw.trim().toLowerCase();
}

/** E-CAT-001 — 2-40 chars, starts alphanumeric, only letters/digits/hyphens after lowering+trimming. */
export function validateKey(raw: string): CatalogValidationResult {
  const value = storedKey(raw ?? '');
  if (value.length < KEY_MIN_LENGTH || value.length > KEY_MAX_LENGTH || !KEY_PATTERN.test(value)) {
    return {valid: false, code: 'E-CAT-001'};
  }
  return {valid: true};
}

/** E-CAT-003 — 1-80 chars after trim, no HTML tag. */
export function validateLabel(raw: string): CatalogValidationResult {
  const value = (raw ?? '').trim();
  if (value.length < 1 || value.length > LABEL_MAX_LENGTH) {
    return {valid: false, code: 'E-CAT-003'};
  }
  if (HTML_TAG_PATTERN.test(value)) {
    return {valid: false, code: 'E-CAT-003'};
  }
  return {valid: true};
}

/** E-CAT-004 — item_type.unit must be one of each/set/pair. */
export function validateUnit(raw: string): CatalogValidationResult {
  if (!VALID_UNITS.includes(raw as CatalogUnit)) {
    return {valid: false, code: 'E-CAT-004'};
  }
  return {valid: true};
}

/** E-CAT-009 — size_label is grouping text only, never math (D-IR-2). Optional, <=20 chars. */
export function validateSizeLabel(raw: string | null | undefined): CatalogValidationResult {
  if (raw == null || raw === '') return {valid: true};
  if (raw.trim().length > 20) return {valid: false, code: 'E-CAT-009'};
  return {valid: true};
}

/** E-CAT-010 — external_ref: optional, <=60 chars, no HTML. A distinct code from E-CAT-003 so the message names the right limit. */
export function validateExternalRef(raw: string | null | undefined): CatalogValidationResult {
  if (raw == null || raw === '') return {valid: true};
  const value = raw.trim();
  if (value.length > 60 || HTML_TAG_PATTERN.test(value)) {
    return {valid: false, code: 'E-CAT-010'};
  }
  return {valid: true};
}
