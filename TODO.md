# TODO

## Next Up

### Real Protect ingest

- Add a thin Protect API client in `ProtectCadenceCore`.
- Implement login/session handling against a local Protect controller.
- Fetch recent event payloads from Protect over HTTP first.
- Keep websocket/realtime work out of the first pass unless polling proves inadequate.

### Ingest pipeline wiring

- Replace `--event-json` fixture-only ingest with real Protect fetch + normalize + insert flow.
- Add a narrow ingest window argument such as `--since` or `--last-hours`.
- Add camera ID to name resolution when the event payload does not include a usable display name.
- Decide whether ignored events should be counted and reported in ingest output.

### Event normalization

- Validate actual Protect event payloads against the current `ProtectEventPayload` model.
- Confirm which timestamp field is most reliable for `timeStart`.
- Confirm whether `timeEnd` is usually present and useful.
- Review whether `licensePlate` should remain out of the base table.
- Review whether audio smart-detect kinds should live in the same `kind` namespace as object detections.

### Query surface

- Implement `protect-cadence-query summary`.
- Add time window flags shared across query commands.
- Decide on one stable JSON output shape for agent consumption.
- Add grouped counts by camera and kind.

### Schema and migrations

- Keep the base table as tall event rows unless real query pressure says otherwise.
- Consider adding raw payload archival outside the main table if debugging or trust needs it.
- Decide whether `event_id + kind` is the right long-term dedupe key after seeing real Protect payloads.

### Tests and fixtures

- Add sample Protect event fixtures captured from real responses.
- Test ingest against mixed payloads: smart detect, motion-only, missing camera names, duplicate events.
- Add migration tests for upgrading from older local schemas.

## Current State

- SQLite database and migrations exist.
- Base event schema is `time_start`, `time_end`, `camera`, `kind`, `event_id`.
- One Protect event can normalize into multiple rows.
- `protect-cadence-query recent` works against local SQLite.
- `protect-cadence-ingest --event-json <file>` works for local fixture ingestion.
