// VAL-1 (US-VAL-1-01) — The field rules registry: one entry per input
// that VAL-1 covers, keyed "entity.field". A backend copy of the SAME
// entries lives in functions/validate_field.xs (kept in sync by hand —
// same pattern as OBS-1's error catalog; see that file's header for
// why there is no shared build step).
import rulesJson from './fieldRules.json';
import type {FieldRule} from './validate';

export const fieldRules: Record<string, FieldRule> = rulesJson as Record<string, FieldRule>;

export function getFieldRule(key: string): FieldRule | undefined {
  return fieldRules[key];
}

/** Every allowedValues entry must be non-empty for an enum rule, and every error code must be a real catalog code (checked separately, against errorCatalog). */
export function validateRegistryShape(rules: Record<string, FieldRule>): string[] {
  const problems: string[] = [];
  for (const [key, rule] of Object.entries(rules)) {
    if (rule.type === 'enum' && (!rule.allowedValues || rule.allowedValues.length === 0)) {
      problems.push(`${key}: enum rule has no allowedValues`);
    }
    if (!rule.errorCodes || Object.keys(rule.errorCodes).length === 0) {
      problems.push(`${key}: no errorCodes declared`);
    }
    const expectedKey = `${rule.entity}.${rule.field}`;
    if (key !== expectedKey) {
      problems.push(`${key}: registry key does not match entity.field ("${expectedKey}")`);
    }
  }
  return problems;
}
