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
- Decide whether `recent` should stay as a narrow convenience command or evolve into a more general filtered events query.
- Add explicit time window controls beyond `--last-hours`, likely `--since` and `--until`.
- Add extraction-oriented filters for `kind` and `camera`.
- Add native time-of-day filtering, including overnight ranges such as `22:00-05:00`.
- Add a query shape for “all matching rows in this time window and these hours of day”.
- Add grouped summary bucketing beyond camera+kind only when there is a clear question behind it.
- Likely useful buckets: `date`, `hour-of-day`, and `day-of-week`.
- Decide how count semantics should be exposed when row counts and distinct-event counts differ.
- Add `compare` only if it remains a descriptive evidence-extraction tool rather than embedded reasoning.
- Consider a later baseline/profile command only if it stays mathematical and obviously simpler than doing the same work in OpenClaw.

### Schema and migrations

- Keep the base table as tall event rows unless real query pressure says otherwise.
- Consider adding raw payload archival outside the main table if debugging or trust needs it.
- Decide whether `event_id + kind` is the right long-term dedupe key after seeing real Protect payloads.
- If query pressure grows, prefer indexes and clear SQL over schema growth first.
- If Protect identity semantics are messy, prefer a narrow explicit ingest-side solution over broad schema growth.

### Tests and fixtures

- Add migration tests for upgrading from older local schemas.
- Add one end-to-end CLI smoke test for `protect-cadence-ingest --last-hours` with stubbed transport if the current runner shape stays stable.

## Current State

- SQLite database and migrations exist.
- Base event schema is `time_start`, `time_end`, `camera`, `kind`, `event_id`.
- One Protect event can normalize into multiple rows.
- `protect-cadence-ingest --last-hours <n>` fetches bounded recent events from a Protect controller.
- `protect-cadence-ingest --event-json <file>` replays one event object or an array of event objects.
- `protect-cadence-ingest --camera-json <file>` can supply camera ID to name lookup during replay.
- `protect-cadence-ingest --write-api-snapshot-dir <dir>` writes sanitized event and camera fixtures plus a schema snapshot.
- `protect-cadence-query recent` works against local SQLite.
- `protect-cadence-query summary` works against local SQLite.
- `Docs/protect-api-contract.md` plus `Tests/Fixtures/ProtectAPI/` record the current ingest-side Protect API contract.
- The package is currently an extraction-oriented local event store; reasoning is expected to happen in downstream tools such as OpenClaw.
