const { test } = require('node:test');
const assert = require('node:assert/strict');
const gate = require('./release_ci_gate.cjs');
const good = { id: 1, head_sha: 'abc', repository: { full_name: 'owner/repo' },
  event: 'push', status: 'completed', conclusion: 'success', html_url: 'https://example.invalid/ci' };
async function check(runs) {
  let output;
  await gate({
    context: { repo: { owner: 'owner', repo: 'repo' }, sha: 'abc' },
    github: { rest: { actions: { listWorkflowRuns: 'endpoint' } }, paginate: async (_, args) => {
      assert.equal(args.workflow_id, 'ci.yml'); assert.equal(args.head_sha, 'abc'); return runs;
    } },
    core: { setOutput: (key, value) => { assert.equal(key, 'reuse'); output = value; }, info: () => {} },
  });
  return output;
}
test('reuse completed exact-commit CI', async () => assert.equal(await check([good]), 'true'));
test('missing CI falls back', async () => assert.equal(await check([]), 'false'));
test('wrong commit, fork and PR cannot authorize release', async () => {
  for (const change of [{ head_sha: 'other' }, { repository: { full_name: 'fork/repo' } }, { event: 'pull_request' }]) {
    assert.equal(await check([{ ...good, ...change }]), 'false');
  }
});
test('newer failed or running CI invalidates older success', async () => {
  for (const change of [{ conclusion: 'failure' }, { status: 'in_progress' }, { conclusion: 'cancelled' }]) {
    assert.equal(await check([good, { ...good, id: 2, ...change }]), 'false');
  }
});
test('API error fails closed', async () => {
  await assert.rejects(gate({ github: { rest: { actions: {} }, paginate: async () => { throw Error('API unavailable'); } },
    context: { repo: {}, sha: 'abc' }, core: { setOutput: () => assert.fail('must not authorize') } }));
});
