// Validates policies.cedar against schema.cedarschema with Cedar's validator.
import { readFileSync } from 'node:fs';
import * as cedar from '@cedar-policy/cedar-wasm/nodejs';
import { loadPolicies } from '../src/workflow.ts';

const schema = readFileSync(new URL('../schema.cedarschema', import.meta.url), 'utf8');
const policies = loadPolicies();
const answer = cedar.validate({ schema, policies: { staticPolicies: policies } });

if (answer.type !== 'success') {
  console.error('validation could not run:', JSON.stringify(answer.errors, null, 2));
  process.exit(1);
}
for (const w of answer.validationWarnings) console.warn(`warning in ${w.policyId}: ${w.error.message}`);
if (answer.validationErrors.length > 0) {
  for (const e of answer.validationErrors) console.error(`error in ${e.policyId}: ${e.error.message}`);
  process.exit(1);
}
const ids = Object.keys(policies).sort();
if (ids.join(',') !== 'P1,P2,P3,P4,P5') {
  console.error(`expected policies P1..P5, found ${ids.join(',')}`);
  process.exit(1);
}
console.log(`ok: ${ids.length} policies valid against the schema (Cedar ${cedar.getCedarVersion()})`);
