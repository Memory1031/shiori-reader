// Match the exact release commit in this repository's canonical CI workflow.
module.exports = async function ({ github, context, core }) {
  const runs = await github.paginate(github.rest.actions.listWorkflowRuns, {
    ...context.repo,
    workflow_id: 'ci.yml',
    head_sha: context.sha,
    per_page: 100,
  });
  const candidates = runs.filter(run =>
    run.head_sha === context.sha &&
    run.repository?.full_name === `${context.repo.owner}/${context.repo.repo}` &&
    ['push', 'workflow_dispatch'].includes(run.event));
  // A newer failed/running run must not be hidden by an older green result.
  candidates.sort((a, b) => b.id - a.id);
  const latest = candidates[0];
  const reusable = latest?.status === 'completed' && latest.conclusion === 'success';
  core.setOutput('reuse', reusable ? 'true' : 'false');
  core.info(reusable
    ? `Reusing CI ${latest.html_url} for ${context.sha}`
    : 'No successful latest CI for this exact commit; run the shared quality workflow.');
};
