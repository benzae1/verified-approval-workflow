import type { EntityJson, EntityUidJson } from '@cedar-policy/cedar-wasm/nodejs';
import type { Mutant } from './mutants.ts';
import type { Action, State } from './workflow.ts';

/**
 * Builds the policy engine's input: Cedar entities from a workflow state, and
 * a Cedar request from an action. Mirrors `toEntities` and `toRequest` in
 * lean/Workflow/Bridge.lean. The proofs cover the Lean version. This version
 * is tested against it.
 */

type Uid = { type: string; id: string };

export const userUid = (name: string): Uid => ({ type: 'User', id: name });
export const requestUid = (id: number): Uid => ({ type: 'Request', id: String(id) });
export const APPROVERS: Uid = { type: 'Group', id: 'approvers' };
export const QUEUE: Uid = { type: 'Queue', id: 'default' };
const actionUid = (id: string): Uid => ({ type: 'Action', id });

/**
 * All entities of a state: the approver group, the queue, one entity per
 * approver, one per request. Users without approval rights need no entity:
 * they have no attributes and no parents.
 */
export function toEntities(state: State, mutant?: Mutant): EntityJson[] {
  const entities: EntityJson[] = [
    { uid: APPROVERS, attrs: {}, parents: [] },
    { uid: QUEUE, attrs: {}, parents: [] },
  ];
  for (const name of state.approvers) {
    entities.push({ uid: userUid(name), attrs: {}, parents: [APPROVERS] });
  }
  state.requests.forEach((r, id) => {
    entities.push({
      uid: requestUid(id),
      attrs:
        mutant === 'M4'
          ? { status: r.status } // M4: `requester` forgotten
          : { requester: { __entity: userUid(r.requester) }, status: r.status },
      parents: [],
    });
  });
  return entities;
}

export interface CedarRequest {
  principal: EntityUidJson;
  action: EntityUidJson;
  resource: EntityUidJson;
}

export function toRequest(actor: string, a: Action): CedarRequest {
  const principal = userUid(actor);
  switch (a.action) {
    case 'create':
      return { principal, action: actionUid('createRequest'), resource: QUEUE };
    case 'edit':
      return { principal, action: actionUid('editRequest'), resource: requestUid(a.id) };
    case 'approve':
      return { principal, action: actionUid('approve'), resource: requestUid(a.id) };
    case 'deny':
      return { principal, action: actionUid('deny'), resource: requestUid(a.id) };
    case 'delegate':
      return { principal, action: actionUid('delegate'), resource: userUid(a.to) };
  }
}
