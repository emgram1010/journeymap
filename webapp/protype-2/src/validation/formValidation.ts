// VAL-1 (US-VAL-1-04) — Pure form-validation logic, consumed by the
// useFormValidation hook. Kept separate from React so it is directly
// unit-testable (this repo has no DOM-rendering test setup — see
// CLAUDE.md — so UI components stay thin wrappers around pure logic
// like this, checked by inspection rather than a render test).
import {validate, type FieldRule, type ValidateResult} from './validate';

export interface FormFieldState {
  value: string;
  error: string | null; // the message to show inline, or null when valid
  code: string | null;
}

export type FormState = Record<string, FormFieldState>;

/** Validates every field in `values` against its rule and builds the per-field state a form renders from. */
export function runFormValidation(values: Record<string, string>, rules: Record<string, FieldRule>): FormState {
  const state: FormState = {};
  for (const [key, rule] of Object.entries(rules)) {
    const raw = values[key] ?? '';
    const result: ValidateResult = validate(raw, rule);
    state[key] = result.ok
      ? {value: String(result.value), error: null, code: null}
      : {value: raw, error: result.message, code: result.code};
  }
  return state;
}

export function isFormValid(state: FormState): boolean {
  return Object.values(state).every((field) => field.error === null);
}

export function firstError(state: FormState): {key: string; error: string} | null {
  for (const [key, field] of Object.entries(state)) {
    if (field.error !== null) return {key, error: field.error};
  }
  return null;
}

export function errorCount(state: FormState): number {
  return Object.values(state).filter((field) => field.error !== null).length;
}

/**
 * A rejected SAVE (server-side) must never clear what the user typed.
 * This merges a server rejection into existing field state without
 * touching `value` on any field — only the error/code on the named
 * field (or, when the rejection has no field, every field keeps its
 * state and the caller shows the message in a banner instead).
 */
export function applyServerRejection(
  state: FormState,
  rejection: {field: string | null; code: string; message: string},
): FormState {
  if (rejection.field === null || !(rejection.field in state)) return state;
  return {
    ...state,
    [rejection.field]: {...state[rejection.field], error: rejection.message, code: rejection.code},
  };
}
