# Findings — contract lens — sprint 1 round 0

Definition of done resolved via flat-mode `Spec:` header in
`docs/superpowers/plans/2026-09-08-streamline-experiments-harness.md` →
`docs/superpowers/specs/2026-09-08-streamline-experiments-harness-design.md`
(`## Success Criteria`, lines 75-98). Sprint 1's contract covers a subset of
that definition of done (the two dedup criteria matching plan tasks 1-2);
per-sprint Success-Criteria coverage is explicitly out of scope for this
lens.

### C1: experiments/lib/output.sh exists and none of the four runner files still define log() inline

No findings. `test -f ... && ! grep -qE '^log\(\)' <4 files>` can fail (a
builder who leaves any inline `log()` definition makes the negated grep
exit 0, negated to nonzero). The criterion's own claim is structural
(dedup of a function definition's location), not runtime behavior of
`log()`, so a presence/absence grep is the correct check for what this
criterion asserts — not a test-2 presence-check failure, and not
grep-standing-in-for-runnable-interface since no invocable behavior is
being claimed here.

### C2: exactly one file in experiments/lib/ contains the report header and neither old runner still embeds the report writer inline

No findings. `[ "$(grep -rl 'Integration Test Report' experiments/lib/ | wc -l)" -eq 1 ] && ! grep -q ... dpdk/run_experiment.sh && ! grep -q ... baseline-tcp/run_experiment.sh`
can fail on a plausible bad implementation (report header left duplicated,
or old runner still embeds it). The criterion is a structural
one-definition claim, matching what the grep asserts.

No findings under this lens.
