// VAL-1 (US-VAL-1-04) — Inline field error. No render tests exist in
// this repo (no DOM/testing-library setup — see CLAUDE.md); this stays
// a thin, inspectable wrapper over the tested FormFieldState shape.
import React from 'react';

export interface FieldErrorProps {
  error: string | null;
  /** Shown next to the label when the field is required, independent of whether it currently has an error. */
  required?: boolean;
}

export default function FieldError({error, required}: FieldErrorProps) {
  if (!error) {
    return required ? <span className="text-xs text-zinc-400">Required</span> : null;
  }
  return (
    <p className="text-xs text-red-600 mt-1" role="alert">
      {error}
    </p>
  );
}
