# TODO

## Next Up

### Real controller validation

Completed on 2026-03-27 via live `protect-cadence validate` runs against the local controller.

Confirmed:
- live samples currently use `id` rather than `eventID` as the practical source-event identifier
- `detectedAt` was absent in sampled live events, so current practical behavior is `timeStart = start` even though `detectedAt ?? start` remains a safe rule
- settled/open behavior under `end != nil` is meaningful on current live data; a live Den-camera motion run produced an unsettled event with no `end`
- the current dedupe key shape (`source event id + normalized kind`) showed no collision pressure in sampled live data
- multi-kind smart-detect events are real and still support the current normalization model

Follow-up later if useful:
- capture and commit a fresh sanitized snapshot with `--write-api-snapshot-dir`
- rerun validation occasionally if Protect firmware / API behavior changes materially

### API contract drift

- Compare real controller payloads to `Docs/protect-api-contract.md`.
- Extend `ProtectEventPayload` only if real data requires additional fields for ingest.
- Decide whether audio smart-detect kinds should remain ignored or join the base `kind` namespace.
- Decide whether `licensePlate` should remain a direct kind in the base table.

### Fixture refresh workflow

- Decide whether fixture refresh should stay as the current test-driven maintenance flow or move to a dedicated helper command later.
- Capture one more sample window from a real controller once credentials and safe sample data are available.
- Keep the checked-in fixtures intentionally small so schema diffs stay legible.

### Query surface

Completed recently:
- shared query-bound parsing now accepts `--since` / `--until` in both ISO 8601 and simple host-local deterministic forms
- recurring human-time filters now include repeatable `--day-of-week` plus `--weekday` and `--weekend`
- the first `compare` slice now exists for window-to-window descriptive comparisons
- public count semantics now keep normalized event rows as the primary counts, with distinct source-event counts framed separately

Still open:
- Extend `compare` beyond the first window-to-window slice only when the next shape stays obviously descriptive.
  - `--vs-prior-window`, `--vs-same-window-last-week`, `--vs-window-before`, and `--vs-window-after` now exist; later helpers can build from the current compare-mode model.
  - Likely later helpers: multi-week weekday baselines or one camera vs another camera.
  - Preserve the current zero/empty-bucket behavior with explicit regression tests so absences remain inspectable evidence.
  - Keep it mathematical and evidence-oriented; do not add anomaly judgments.
- Add a drill-down path from aggregate output to representative raw events so downstream tools can inspect the evidence behind a bucket.
  - The base drill-down descriptor now exists on summary/compare groups and points back to `events` with exact bucket filters.
  - Follow up only if downstream tools need richer drill-down metadata beyond the current `events`-targeted descriptor shape.
- Add distribution-oriented summaries so downstream tools can learn rhythms rather than just totals.
  - Examples: counts by hour-of-day, day-of-week, and camera within a window.
  - Keep outputs descriptive and evidence-oriented; do not label anything normal or abnormal.
- Consider named periods such as `dawn`, `day`, `dusk`, `night` if they can be defined clearly.
- Later, only if useful, add business-hours / overnight style presets.
- Consider a baseline/profile-style command only if it stays mathematical, legible, and clearly simpler than doing the same work in OpenClaw.
- Explore whether session / cluster style outputs are useful for collapsing noisy repeated detections into activity episodes.
  - If added, keep the primitive explicit, such as grouping events separated by less than an N-minute quiet gap.
  - Treat this as a descriptive view over events, not an interpretation layer.

### OpenClaw-facing pattern-reading support

These are not requests for embedded anomaly scoring. They are requests for query and filter tools that let OpenClaw judge what is unusual.

- Make it easy to compare one slice to another:
  - same hour yesterday
  - same weekday across prior weeks
  - before/after a date or change
  - prior-window comparisons
  - one camera vs another camera
  - preserve empty / zero-result buckets when the peer slice had activity so absences are queryable evidence
- Make it easy to move from “summary suggests something interesting” to “show me the underlying events” in one hop.
- Make it easy to inspect shape, not just totals:
  - when a camera usually fires
  - when a given kind usually appears
  - how activity distributes across hours and weekdays
- Make it easy to collapse noisy repetition when needed:
  - adjacent rows within N minutes
  - quiet-gap sessionization for repeated detections
- Keep all of this descriptive. The CLI should expose evidence cleanly; OpenClaw should remain the judge of anomalies and household patterns.

### Cadence modeling layer

See `Docs/cadence-modeling-layer.md`.

Near-term direction:
- treat the modeling layer as a separate derived artifact, preferably a parallel SQLite database
- keep `protect-cadence` as the source evidence store, with modeled state rebuildable from cadence events
- start with deterministic episode clustering before adding more ambitious sequence modeling
- add simple time-conditioned state frequency and transition statistics before attempting more elaborate anomaly methods
- emit descriptive attention findings for OpenClaw to interpret, not final anomaly judgments
- preserve one-hop drill-down from attention findings back to episodes and source events

First implementation slice:
Completed on 2026-04-14:
- `protect-cadence model rebuild` now rebuilds a separate sibling model SQLite database from the evidence DB
- deterministic episode clustering now materializes `episodes`, `episode_events`, and `episode_kinds`
- the first state vocabulary is `camera:primary_kind`
- first-pass `state_bucket_stats` now bucket by local hour-of-day plus `weekday` / `weekend`
- `state_transition_stats` now materialize same-camera consecutive `from_state -> to_state` transition counts plus simple gap summaries
- `protect-cadence model episodes` and `protect-cadence model findings` now expose modeled episodes plus first-pass `unexpected_presence`, `unexpected_transition`, and `unusual_duration` findings
- `unexpected_transition` currently only covers rare time-bucketed occurrences of otherwise repeated transition pairs

Still open:
- add absence-style findings only after the current episode/state layer proves useful
- decide whether transition findings should later account for exact transition timing or stronger source-state expectations beyond the current repeated-pair bucket rarity check
- decide whether `unusual_duration` should remain long-only or broaden to shorter-than-usual episodes later
- add a small stats/query surface for inspecting `state_bucket_stats` directly if downstream tools ask for it
- add a small stats/query surface for inspecting `state_transition_stats` directly if downstream tools ask for it
- decide whether model rebuilds should eventually accept explicit training/scoring windows instead of using the full evidence DB
- keep the model database rebuild-only for now; do not add incremental refresh machinery until there is real operator pressure

### Schema and migrations

- Keep the base table as tall event rows unless real query pressure says otherwise.
- Consider adding raw payload archival outside the main table if debugging or trust needs it.
- Decide whether `event_id + kind` is the right long-term dedupe key after seeing real Protect payloads.
- If query pressure grows, prefer indexes and clear SQL over schema growth first.
- If Protect identity semantics are messy, prefer a narrow explicit ingest-side solution over broad schema growth.
- If this repo starts ingesting multiple controllers or other sources, decide whether controller/source identity belongs in the base schema or at an ingest boundary. Do not guess at that shape early.

### Tests and fixtures

- Add migration tests for upgrading from older local schemas.
- Add one end-to-end CLI smoke test for `protect-cadence-ingest --last-hours` with stubbed transport if the current runner shape stays stable.

### CLI / operator surface follow-up

- Bare `protect-cadence validate` now resolves through the same parser layer as other commands; keep it that way if the CLI surface is reshaped again.
- Revisit whether `validate` should remain a first-class public subcommand long-term or move behind a more operator-facing / maintenance-oriented surface once the validation workflow stabilizes.

## Current State

- SQLite database and migrations exist.
- Base event schema is `time_start`, `time_end`, `camera_id`, `camera`, `event_type`, `kind`, `event_id`.
- Normalized cadence rows are treated as the primary public event unit.
- One Protect event can still normalize into multiple stored events when multiple kinds are present.
- `protect-cadence-ingest --last-hours <n>` fetches bounded recent events from a Protect controller.
- `protect-cadence-ingest --event-json <file>` replays one event object or an array of event objects.
- `protect-cadence-ingest --camera-json <file>` can supply camera ID to name lookup during replay.
- `protect-cadence-ingest --write-api-snapshot-dir <dir>` writes sanitized event and camera fixtures plus a schema snapshot.
- `protect-cadence-query recent` works against local SQLite.
- `protect-cadence-query summary` works against local SQLite.
- `Docs/protect-api-contract.md` plus `Tests/Fixtures/ProtectAPI/` record the current ingest-side Protect API contract.
- The package is currently an extraction-oriented local event store; reasoning is expected to happen in downstream tools such as OpenClaw.
