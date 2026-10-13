// GOV-1 (US-GOV-1-04) — Standalone schema conformance report.
//
// The audit also runs automatically as part of `npm test` in
// webapp/protype-2 (src/ops/schemaAudit.test.ts), which FAILS the build
// on any error-level finding. This script is the human-readable version:
// it prints every finding, warnings included, so you can see the
// grandfathered debt on the older tables too.
//
// Run it from the webapp/protype-2 directory, which is where tsx lives:
//
//   cd webapp/protype-2 && node --import tsx ../../scripts/audit-schema.mjs
//
// Exit code is 1 when there is any error-level finding, 0 otherwise.
import {readFileSync, readdirSync} from 'node:fs';
import {join, dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {auditAll, errorsOnly, formatFindings} from '../webapp/protype-2/src/ops/schemaAudit.ts';

const repoRoot = join(dirname(fileURLToPath(import.meta.url)), '..');
const tablesDir = join(repoRoot, 'static', 'tables');

const files = readdirSync(tablesDir)
  .filter((f) => f.endsWith('.xs'))
  .map((fileName) => ({fileName, text: readFileSync(join(tablesDir, fileName), 'utf8')}));

const findings = auditAll(files);
const errors = errorsOnly(findings);
const warnings = findings.filter((f) => f.severity === 'warning');

console.log(`Schema audit — ${files.length} tables`);
console.log(`  ${errors.length} error(s), ${warnings.length} warning(s)\n`);

if (findings.length > 0) console.log(formatFindings(findings));

if (errors.length > 0) {
  console.log('\nErrors are on NEW tables (id >= 80) and must be fixed. See docs/data-standards.md.');
  process.exit(1);
}

console.log('\nNo errors. Warnings are grandfathered tables; see docs/data-standards.md (S13).');
