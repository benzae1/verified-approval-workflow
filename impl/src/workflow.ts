import { readFileSync } from 'node:fs';
import * as cedar from '@cedar-policy/cedar-wasm/nodejs';
import { toEntities, toRequest } from './entities.ts';
import type { Mutant } from './mutants.ts';

/**
 * The approval workflow, as a library without I/O. `step` mirrors `step` in
 * lean/Workflow/Model.lean. Cedar decides authorization; this file does the
 * lifecycle checks.
 */

export type Status = 'Requested' | 'Approved' | 'Denied';

export interface Req {
  requester: string;
  justification: string;
  status: Status;
  /** Who approved or denied the request; null while it is still open. */
  decidedBy: string | null;
}

export interface State {
  /** The users who currently hold approval rights. */
  approvers: string[];
  /** All requests ever created; request `id` is `requests[id]`. */
  requests: Req[];
}

/**
 * Actions are untrusted input, such as a parsed request body, so an `edit`
 * may carry fields besides the one it may change.
 */
export type Action =
  | { action: 'create'; justification: string }
  | { action: 'edit'; id: number; justification: string; [extra: string]: unknown }
  | { action: 'approve'; id: number }
  | { action: 'deny'; id: number }
  | { action: 'delegate'; to: string };

export interface StepResult {
  /** `allow` if the action was authorized and legal, and took effect. */
  decision: 'allow' | 'deny';
  state: State;
}

export interface Workflow {
  step(state: State, actor: string, a: Action): StepResult;
}

export const initialState = (approvers: string[]): State => ({ approvers: [...approvers], requests: [] });

const POLICY_FILE = new URL('../policies.cedar', import.meta.url);

/** Splits the policy file into its policies, keyed by their `@id` annotation. */
export function loadPolicies(): Record<string, string> {
  const text = readFileSync(POLICY_FILE, 'utf8');
  const parts = cedar.policySetTextToParts(text);
  if (parts.type !== 'success') {
    throw new Error(`cannot parse policies.cedar: ${JSON.stringify(parts.errors)}`);
  }
  const byId: Record<string, string> = {};
  for (const policy of parts.policies) {
    const id = /@id\("([^"]+)"\)/.exec(policy)?.[1];
    if (id === undefined) throw new Error(`policy without @id annotation:\n${policy}`);
    byId[id] = policy;
  }
  return byId;
}

let instances = 0;

/** Creates the workflow. `mutant` switches on a planted bug; only tests pass it. */
export function createWorkflow(mutant?: Mutant): Workflow {
  const policies = loadPolicies();
  if (mutant === 'M1') delete policies['P4']; // M1: segregation-of-duties policy lost

  // Parse the policy set once; later calls refer to it by name.
  const policySetId = `workflow-${instances++}`;
  const parsed = cedar.preparsePolicySet(policySetId, { staticPolicies: policies });
  if (parsed.type !== 'success') {
    throw new Error(`cannot load policies: ${JSON.stringify(parsed.errors)}`);
  }

  function authorized(state: State, actor: string, a: Action): boolean {
    const answer = cedar.statefulIsAuthorized({
      ...toRequest(actor, a),
      context: {},
      preparsedPolicySetId: policySetId,
      entities: toEntities(state, mutant),
    });
    if (answer.type !== 'success') {
      throw new Error(`authorization call failed: ${JSON.stringify(answer.errors)}`);
    }
    return answer.response.decision === 'allow';
  }

  /** Replace request `id` by `f` of itself, provided it exists and is still open. */
  function updateOpen(state: State, id: number, f: (r: Req) => Req, checkStatus = true): State | null {
    const r = state.requests[id];
    if (r === undefined) return null;
    if (checkStatus && r.status !== 'Requested') return null;
    return { ...state, requests: state.requests.map((old, i) => (i === id ? f(old) : old)) };
  }

  /** The state change of an action that has already been authorized. */
  function apply(state: State, actor: string, a: Action): State | null {
    switch (a.action) {
      case 'create': {
        const r: Req = { requester: actor, justification: a.justification, status: 'Requested', decidedBy: null };
        return { ...state, requests: [...state.requests, r] };
      }
      case 'edit':
        return updateOpen(state, a.id, (r) =>
          mutant === 'M2'
            ? { ...r, ...pick(a, ['justification', 'requester']) } // M2: takes `requester` from the input
            : { ...r, justification: a.justification },
        );
      case 'approve':
        return updateOpen(
          state,
          a.id,
          (r) => ({ ...r, status: 'Approved', decidedBy: actor }),
          mutant !== 'M3', // M3: status check dropped
        );
      case 'deny':
        return updateOpen(state, a.id, (r) => ({ ...r, status: 'Denied', decidedBy: actor }));
      case 'delegate':
        return state.approvers.includes(a.to) ? state : { ...state, approvers: [...state.approvers, a.to] };
    }
  }

  function step(state: State, actor: string, a: Action): StepResult {
    const unchecked = mutant === 'M5' && a.action === 'deny'; // M5: no authorization check on deny
    if (!unchecked && !authorized(state, actor, a)) return { decision: 'deny', state };
    const next = apply(state, actor, a);
    return next === null ? { decision: 'deny', state } : { decision: 'allow', state: next };
  }

  return { step };
}

/** The listed string-valued fields of an untrusted object. */
function pick<K extends string>(input: Record<string, unknown>, keys: K[]): Partial<Record<K, string>> {
  const out: Partial<Record<K, string>> = {};
  for (const k of keys) {
    const v = input[k];
    if (typeof v === 'string') out[k] = v;
  }
  return out;
}
