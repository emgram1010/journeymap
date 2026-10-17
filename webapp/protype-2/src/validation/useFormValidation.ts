// VAL-1 (US-VAL-1-04) — Thin React wrapper around the pure logic in
// formValidation.ts. Kept thin on purpose: every decision (what's
// valid, what the message says, whether a server rejection clears
// anything) lives in the tested pure functions; this hook only holds
// React state and calls them.
import {useCallback, useState} from 'react';
import type {FieldRule} from './validate';
import {runFormValidation, isFormValid, applyServerRejection, type FormState} from './formValidation';

export interface UseFormValidationResult {
  values: Record<string, string>;
  state: FormState;
  isValid: boolean;
  /** Updates one field's typed value AND re-runs validation for it (and only it stays in sync — the rest keep their last-computed state until the next full validate). */
  setValue: (key: string, value: string) => void;
  /** Re-validates every field against the current values. Call before submit. */
  validateAll: () => boolean;
  /**
   * Merges a server-side rejection in. NEVER clears `values` — this is
   * the guarantee that a rejected save never loses what the user typed
   * (E2E-VAL-1-02).
   */
  applyRejection: (rejection: {field: string | null; code: string; message: string}) => void;
}

export function useFormValidation(rules: Record<string, FieldRule>, initialValues: Record<string, string> = {}): UseFormValidationResult {
  const [values, setValues] = useState<Record<string, string>>(initialValues);
  const [state, setState] = useState<FormState>(() => runFormValidation(initialValues, rules));

  const setValue = useCallback(
    (key: string, value: string) => {
      setValues((prev) => {
        const next = {...prev, [key]: value};
        setState(runFormValidation(next, rules));
        return next;
      });
    },
    [rules],
  );

  const validateAll = useCallback(() => {
    const nextState = runFormValidation(values, rules);
    setState(nextState);
    return isFormValid(nextState);
  }, [rules, values]);

  const applyRejection = useCallback((rejection: {field: string | null; code: string; message: string}) => {
    setState((prev) => applyServerRejection(prev, rejection));
    // `values` is deliberately untouched here — see the doc comment.
  }, []);

  return {values, state, isValid: isFormValid(state), setValue, validateAll, applyRejection};
}
