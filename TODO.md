# TODO

## Protect Boundary

- Compare new live controller samples against [Docs/protect-api-contract.md](Docs/protect-api-contract.md) when Protect firmware changes materially.
- Extend `ProtectEventPayload` only when real controller data requires it for ingest or validation.
- Decide whether audio smart-detect kinds should stay ignored or join the base `kind` namespace.
- Decide whether `licensePlate` should stay a direct base kind or move behind a narrower normalization rule.
- Capture a fresh sanitized real-controller snapshot when a materially new API shape appears.

## Evidence Query Surface

- Add new summary dimensions only when current descriptive distributions
  (`camera`, `kind`, `date`, `hour`, and `weekday`) cannot answer a real question cleanly.
- Extend comparison helpers only while they stay descriptive and evidence-oriented.
  Likely next shapes: before/after a specific change or one camera versus another camera.
- Preserve zero and empty buckets whenever the peer slice had activity so absences remain queryable evidence.
- Decide whether named periods such as `dawn`, `day`, `dusk`, and `night` are clear enough to justify first-class filters.
- Revisit quiet-gap or sessionized views only if repeated detections make raw row slices too noisy for downstream tools.

## Drill-Down And Agent Ergonomics

- Keep the current summary/compare drill-down descriptors stable enough for agents to rely on.
- Add richer drill-down metadata only if downstream tools need more than an exact `query events` slice.
- Consider whether a small shared query grammar object should become a documented contract for OpenClaw-facing integrations.
- Use [Docs/pattern-intelligence-proposal.md](Docs/pattern-intelligence-proposal.md) to guide any Datasette/read-only audit docs, stable evidence-output fields, future Robut-composed House Activity Almanac/Guide material, and correction/privacy boundary work.

## Derived Model Database

- Add absence-style findings only if the current episode and state layer proves useful enough to justify them.
- Decide whether transition findings need stronger timing expectations beyond the current repeated-pair bucket rarity check.
- Decide whether `unusual_duration` should remain long-only or broaden to shorter-than-usual episodes later.
- Add direct inspection commands for `state_bucket_stats` and `state_transition_stats` only if downstream tools actually need them.
- Decide whether model rebuilds should accept explicit training and scoring windows instead of rebuilding from the full evidence DB.
- Keep the model DB rebuild-only until there is real operator pressure for incremental refresh.

## Storage And Schema

- Keep the evidence table tall unless repeated query pressure justifies a real schema change.
- Recheck whether `event_id + kind` remains the right dedupe key as more real controller samples accumulate.
- Prefer indexes and clear SQL before adding columns.
- Consider raw payload archival only if debugging or operator trust requires it outside the main evidence table.
- If multi-controller ingest ever becomes real, decide whether controller identity belongs in the evidence schema or stays at the ingest boundary.

## Fixtures And Verification

- Keep checked-in fixtures intentionally small so diffs stay legible.
- Decide whether fixture refresh should remain test-driven or move to a dedicated maintenance command later.
- Keep repo-local verification explicit about `--db`, `--config`, and `--model-db` paths.
- Add a small repo-local smoke path for fixture ingest plus model rebuild if the current runner surface stabilizes further.

## Operator Surface

- Revisit whether `validate` should remain a first-class command or move behind a narrower maintenance surface once the workflow is stable.
- Keep the command set small and prefer shared filter grammar over bespoke one-off subcommands.
- Continue treating downstream reasoning as an external concern. The CLI should expose evidence, not judgments.
