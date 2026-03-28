# TODO

## Next Up

### Real controller validation

- Run the new bounded HTTP ingest against a real local Protect controller.
- Capture a small fresh sanitized snapshot with `--write-api-snapshot-dir`.
- Confirm whether `detectedAt ?? start` is still the right `timeStart` rule on real recent events.
- Confirm whether settled-event filtering by `end != nil` matches how Protect exposes finished detections in practice.
- Check whether any real event shape pressures `event_id + kind` as the dedupe key.

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

- Add a shared filter grammar across query commands.
- Decide whether `recent` should stay as a narrow convenience command or evolve into canonical `events` plus a compatibility alias.
- Add explicit time window controls beyond `--last-hours`, likely `--since` and `--until`.
- Add extraction-oriented filters for `kind` and `camera`.
- Add native time-of-day filtering, including overnight ranges such as `22:00-05:00`.
- Add a query shape for “all matching events in this time window and these hours of day”.
- Add recurring human-time filters that help downstream pattern reading without interpretation:
  - `--weekday` / `--weekend`
  - named periods such as `dawn`, `day`, `dusk`, `night` if they can be defined clearly
  - later, only if useful, business-hours / overnight style presets
- Add grouped summary bucketing beyond camera+kind only when there is a clear question behind it.
- Likely useful buckets: `date`, `hour-of-day`, and `day-of-week`.
- Add distribution-oriented summaries so downstream tools can learn rhythms rather than just totals.
  - Examples: counts by hour-of-day, day-of-week, and camera within a window.
  - Keep outputs descriptive and evidence-oriented; do not label anything normal or abnormal.
- Keep event counts as the primary public count semantics.
- Keep any counts derived from distinct Protect `event_id` framed as source/provenance metadata.
- Extend `compare` beyond the first window-to-window slice only when the next shape stays obviously descriptive.
  - Likely next useful helpers: same weekday across prior weeks, before/after a date, or one camera vs another camera.
  - Keep it mathematical and evidence-oriented; do not add anomaly judgments.
- Add a drill-down path from aggregate output to representative raw events so downstream tools can inspect the evidence behind a bucket.
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
  - one camera vs another camera
- Make it easy to inspect shape, not just totals:
  - when a camera usually fires
  - when a given kind usually appears
  - how activity distributes across hours and weekdays
- Make it easy to collapse noisy repetition when needed:
  - adjacent rows within N minutes
  - quiet-gap sessionization for repeated detections
- Make it easy to move from “summary suggests something interesting” to “show me the underlying events” in one hop.
- Keep all of this descriptive. The CLI should expose evidence cleanly; OpenClaw should remain the judge of anomalies and household patterns.

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
