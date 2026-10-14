// VAL-1 (US-VAL-1-02) — The shared rule engine. "Shared" means this
// exact behaviour, not this exact code: functions/validate_field.xs
// implements the same rules in XanoScript and is proved equal via
// golden fixtures (validate.goldenFixtures.test.ts), the same pattern
// as OBS-1's error catalog.
//
// This module never throws. validate() always returns a result object;
// the caller (a form, or an API endpoint) decides what to do with it.
import {normalizeText, type NormalizeStep} from './normalize';

export type FieldType = 'text' | 'int' | 'decimal' | 'enum' | 'date' | 'time';

export interface FieldRule {
  entity: string;
  field: string;
  label: string;
  type: FieldType;
  required: boolean;
  minLength?: number;
  maxLength?: number;
  min?: number;
  max?: number;
  /** enum only. */
  allowedValues?: string[];
  /** text only: reject a value that contains an HTML tag. */
  noHtml?: boolean;
  normalize?: NormalizeStep[];
  errorCodes: {
    required?: string;
    tooShort?: string;
    tooLong?: string;
    invalid?: string;
    outOfRange?: string;
    notAllowed?: string;
    html?: string;
  };
}

export type ValidateResult =
  | {ok: true; value: string | number}
  | {ok: false; code: string; message: string};

export type ValidationFailure = {ok: false; code: string; message: string};
export type ValidationSuccess = {ok: true; value: string | number};

/**
 * Narrowing helpers. `if (result.ok)` does NOT discriminate this union in
 * this project, because tsconfig.json does not enable strictNullChecks and
 * without it TypeScript cannot tell the `ok: true` branch from `ok: false`.
 * A user-defined type guard works either way, so callers use these instead
 * of testing `.ok` directly.
 */
export function isValidationFailure(result: ValidateResult): result is ValidationFailure {
  return result.ok === false;
}

export function isValidationSuccess(result: ValidateResult): result is ValidationSuccess {
  return result.ok === true;
}

const HTML_TAG_PATTERN = /<[a-zA-Z][^>]*>/;

function parseNumber(raw: string): number | null {
  const trimmed = raw.trim();
  if (trimmed === '') return null;
  const n = Number(trimmed);
  if (!Number.isFinite(n)) return null; // catches NaN and Infinity (e.g. "1e999")
  return n;
}

const DATE_PATTERN = /^(\d{4})-(\d{2})-(\d{2})$/;

function isValidCalendarDate(raw: string): boolean {
  const match = raw.match(DATE_PATTERN);
  if (!match) return false;
  const [, yearStr, monthStr, dayStr] = match;
  const year = Number(yearStr);
  const month = Number(monthStr);
  const day = Number(dayStr);
  if (month < 1 || month > 12 || day < 1 || day > 31) return false;
  const date = new Date(Date.UTC(year, month - 1, day));
  // Date rolls an invalid day (e.g. Feb 31) into the next month — a
  // round-trip check catches that without a leap-year table.
  return date.getUTCFullYear() === year && date.getUTCMonth() === month - 1 && date.getUTCDate() === day;
}

const TIME_PATTERN = /^([01]\d|2[0-3]):([0-5]\d)$/;

/**
 * Validates a single raw (string) value against a rule. Text values are
 * normalised first (per rule.normalize) and the NORMALISED value is
 * what gets length/content-checked and returned on success — this is
 * why "  hello   world  " passes a maxLength rule sized for "hello
 * world" and why the stored value is always the clean one.
 */
export function validate(raw: string, rule: FieldRule): ValidateResult {
  const fail = (kind: keyof FieldRule['errorCodes'], message: string): ValidateResult => ({
    ok: false,
    code: rule.errorCodes[kind] ?? `E-VAL-${kind}`,
    message,
  });

  if (rule.type === 'text' || rule.type === 'enum') {
    const normalized = normalizeText(raw ?? '', rule.normalize ?? ['trim']);

    if (normalized === '') {
      if (rule.required) return fail('required', `${rule.label} is required.`);
      return {ok: true, value: ''};
    }

    if (rule.noHtml && HTML_TAG_PATTERN.test(normalized)) {
      return fail('html', `${rule.label} can't contain HTML.`);
    }

    if (rule.minLength !== undefined && normalized.length < rule.minLength) {
      return fail('tooShort', `${rule.label} must be at least ${rule.minLength} character${rule.minLength === 1 ? '' : 's'}.`);
    }

    if (rule.maxLength !== undefined && normalized.length > rule.maxLength) {
      return fail('tooLong', `${rule.label} must be ${rule.maxLength} characters or fewer.`);
    }

    if (rule.type === 'enum') {
      const allowed = rule.allowedValues ?? [];
      if (!allowed.includes(normalized)) {
        return fail('notAllowed', `${rule.label} must be one of: ${allowed.join(', ')}.`);
      }
    }

    return {ok: true, value: normalized};
  }

  if (rule.type === 'int' || rule.type === 'decimal') {
    const trimmed = (raw ?? '').trim();

    if (trimmed === '') {
      if (rule.required) return fail('required', `${rule.label} is required.`);
      return {ok: true, value: ''};
    }

    const n = parseNumber(trimmed);
    if (n === null) return fail('invalid', `${rule.label} must be a number.`);
    if (rule.type === 'int' && !Number.isInteger(n)) {
      return fail('invalid', `${rule.label} must be a whole number.`);
    }
    if (rule.min !== undefined && n < rule.min) return fail('outOfRange', `${rule.label} must be at least ${rule.min}.`);
    if (rule.max !== undefined && n > rule.max) return fail('outOfRange', `${rule.label} must be ${rule.max} or less.`);

    return {ok: true, value: n};
  }

  if (rule.type === 'date') {
    const trimmed = (raw ?? '').trim();
    if (trimmed === '') {
      if (rule.required) return fail('required', `${rule.label} is required.`);
      return {ok: true, value: ''};
    }
    if (!isValidCalendarDate(trimmed)) return fail('invalid', `${rule.label} must be a real date (YYYY-MM-DD).`);
    return {ok: true, value: trimmed};
  }

  if (rule.type === 'time') {
    const trimmed = (raw ?? '').trim();
    if (trimmed === '') {
      if (rule.required) return fail('required', `${rule.label} is required.`);
      return {ok: true, value: ''};
    }
    if (!TIME_PATTERN.test(trimmed)) return fail('invalid', `${rule.label} must be a time like 08:00.`);
    return {ok: true, value: trimmed};
  }

  // Unreachable while FieldType stays exhaustive above; fails safe rather than silently passing.
  return fail('invalid', `${rule.label} has an unrecognised rule type.`);
}

/**
 * Validates an end before a start (S-shaped range check), used for any
 * "inverted range" rule (a window's start/end, a date range, ...).
 * Both values must already be validated dates/times of the same shape.
 */
export function validateRangeOrder(
  startRaw: string,
  endRaw: string,
  startLabel: string,
  endLabel: string,
  errorCode: string,
): ValidateResult {
  if (startRaw >= endRaw) {
    return {ok: false, code: errorCode, message: `${endLabel} must be after ${startLabel}.`};
  }
  return {ok: true, value: endRaw};
}
