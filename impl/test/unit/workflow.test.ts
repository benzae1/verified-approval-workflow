// Ordinary example-based unit tests, of the kind one writes while building the
// feature. They were written before the differential test and before the
// planted bugs were run, and are deliberately not tuned to catch them.
//
// Set WORKFLOW_MUTANT=M1..M5 to run them against a planted bug.
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { parseMutant } from '../../src/mutants.ts';
import { type Action, type State, createWorkflow, initialState } from '../../src/workflow.ts';

const workflow = createWorkflow(parseMutant(process.env.WORKFLOW_MUTANT));

/** Runs steps in order; returns the final state and each decision. */
function run(approvers: string[], steps: [actor: string, action: Action][]) {
  let state: State = initialState(approvers);
  const decisions: string[] = [];
  for (const [actor, action] of steps) {
    const result = workflow.step(state, actor, action);
    state = result.state;
    decisions.push(result.decision);
  }
  return { state, decisions };
}

test('any user can create a request', () => {
  const { state, decisions } = run(['bob'], [['alice', { action: 'create', justification: 'db migration' }]]);
  assert.deepEqual(decisions, ['allow']);
  assert.deepEqual(state.requests, [
    { requester: 'alice', justification: 'db migration', status: 'Requested', decidedBy: null },
  ]);
});

test('the requester can edit the justification', () => {
  const { state, decisions } = run(['bob'], [
    ['alice', { action: 'create', justification: 'draft' }],
    ['alice', { action: 'edit', id: 0, justification: 'final' }],
  ]);
  assert.deepEqual(decisions, ['allow', 'allow']);
  assert.equal(state.requests[0]?.justification, 'final');
});

test('nobody else can edit a request', () => {
  const { state, decisions } = run(['bob'], [
    ['alice', { action: 'create', justification: 'draft' }],
    ['bob', { action: 'edit', id: 0, justification: 'hijacked' }],
  ]);
  assert.deepEqual(decisions, ['allow', 'deny']);
  assert.equal(state.requests[0]?.justification, 'draft');
});

test('an approver approves a request and is recorded', () => {
  const { state, decisions } = run(['bob'], [
    ['alice', { action: 'create', justification: 'x' }],
    ['bob', { action: 'approve', id: 0 }],
  ]);
  assert.deepEqual(decisions, ['allow', 'allow']);
  assert.equal(state.requests[0]?.status, 'Approved');
  assert.equal(state.requests[0]?.decidedBy, 'bob');
});

test('an approver denies a request and is recorded', () => {
  const { state, decisions } = run(['bob'], [
    ['alice', { action: 'create', justification: 'x' }],
    ['bob', { action: 'deny', id: 0 }],
  ]);
  assert.deepEqual(decisions, ['allow', 'allow']);
  assert.equal(state.requests[0]?.status, 'Denied');
  assert.equal(state.requests[0]?.decidedBy, 'bob');
});

test('a user without approval rights can neither approve nor deny', () => {
  const { state, decisions } = run(['bob'], [
    ['alice', { action: 'create', justification: 'x' }],
    ['carol', { action: 'approve', id: 0 }],
    ['carol', { action: 'deny', id: 0 }],
  ]);
  assert.deepEqual(decisions, ['allow', 'deny', 'deny']);
  assert.equal(state.requests[0]?.status, 'Requested');
});

test('an approver cannot approve their own request', () => {
  const { state, decisions } = run(['alice', 'bob'], [
    ['alice', { action: 'create', justification: 'x' }],
    ['alice', { action: 'approve', id: 0 }],
  ]);
  assert.deepEqual(decisions, ['allow', 'deny']);
  assert.equal(state.requests[0]?.status, 'Requested');
});

test('a decided request cannot be edited', () => {
  const { state, decisions } = run(['bob'], [
    ['alice', { action: 'create', justification: 'x' }],
    ['bob', { action: 'approve', id: 0 }],
    ['alice', { action: 'edit', id: 0, justification: 'changed afterwards' }],
  ]);
  assert.deepEqual(decisions, ['allow', 'allow', 'deny']);
  assert.equal(state.requests[0]?.justification, 'x');
});

test('an approver can delegate, and the delegate can then approve', () => {
  const { state, decisions } = run(['bob'], [
    ['alice', { action: 'create', justification: 'x' }],
    ['bob', { action: 'delegate', to: 'carol' }],
    ['carol', { action: 'approve', id: 0 }],
  ]);
  assert.deepEqual(decisions, ['allow', 'allow', 'allow']);
  assert.deepEqual(state.approvers, ['bob', 'carol']);
  assert.equal(state.requests[0]?.decidedBy, 'carol');
});

test('a user without approval rights cannot delegate', () => {
  const { state, decisions } = run(['bob'], [['alice', { action: 'delegate', to: 'alice' }]]);
  assert.deepEqual(decisions, ['deny']);
  assert.deepEqual(state.approvers, ['bob']);
});
