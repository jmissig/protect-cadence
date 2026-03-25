# Protect API Contract

This document records the current UniFi Protect API shape that `protect-cadence` relies on for ingest.

It is intentionally narrow. It is not a full Protect schema reference. It is the subset of the API we currently depend on for:

- authenticating
- fetching a bounded event window
- resolving camera IDs to stable camera names
- normalizing event rows into SQLite

The machine-readable companion snapshot lives at `Tests/Fixtures/ProtectAPI/schema-snapshot.json`.

## Endpoints

### Login

- `POST /api/auth/login`
- request body:
  - `username`
  - `password`
  - `rememberMe`
- current assumption:
  - login returns a session cookie in `Set-Cookie`
  - login may also return `x-csrf-token`
  - subsequent private API requests send both the cookie and the csrf header when present

### Events

- `GET /proxy/protect/api/events`
- current query parameters used:
  - `start`
  - `end`
  - `sorting=desc`
- current assumption:
  - response is a JSON array of event objects
  - bounded ingest is driven entirely by explicit start/end timestamps

### Cameras

- `GET /proxy/protect/api/cameras`
- current assumption:
  - response is a JSON array of camera objects
  - ingest only relies on `id`, `displayName`, and `name`

## Event Fields Currently Consumed

- `id`
- `eventId`
- `type`
- `start`
- `end`
- `detectedAt`
- `smartDetectTypes`
- `camera`
- `cameraId`

`camera` is currently treated as one of:

- a string camera identifier
- an embedded object with `id`, `displayName`, and `name`

## Observed Live Capture Notes

The sanitized live capture in `Tests/Fixtures/ProtectAPIReal/` differs from the broader synthetic baseline in a few useful ways.

Current committed live capture version:

- Protect `7.0.94`
- files:
  - `Tests/Fixtures/ProtectAPIReal/events-response-protect-7.0.94.json`
  - `Tests/Fixtures/ProtectAPIReal/cameras-response-protect-7.0.94.json`
  - `Tests/Fixtures/ProtectAPIReal/schema-snapshot-protect-7.0.94.json`

Observed in the March 24, 2026 capture:

- event-list rows used `id` but did not include `eventId`
- event-list rows used `start` and `end` but did not include `detectedAt`
- event-list rows used string `camera` identifiers and did not include embedded camera objects
- event-list rows in that capture did not include `cameraId`
- `smartDetectLine` appeared in live data and still carried `smartDetectTypes`
- most returned rows were plain `motion` events, which explains a high ignored count during ingest

Current implication:

- the synthetic `ProtectAPI` fixtures remain useful because they preserve broader shape coverage
- the real `ProtectAPIReal` fixtures document what the controller actually returned in one recent sample window

## Camera Fields Currently Consumed

- `id`
- `displayName`
- `name`

## Normalization Rules

### Base row fields

Normalized SQLite rows currently store:

- `time_start`
- `time_end`
- `camera_id`
- `camera`
- `event_type`
- `kind`
- `event_id`

Current intent:

- `camera_id` keeps the stable Protect camera identifier when available
- `camera` keeps the resolved human-readable camera name
- `event_type` preserves the original Protect event `type` value, such as `smartDetectZone` or `smartDetectLine`
- normalized row identity still uses `event_id + kind`

### Event identity

- normalized row identity currently uses `event_id + kind`
- one Protect event may become multiple rows when `smartDetectTypes` contains multiple kinds

### Time selection

- `timeStart = detectedAt ?? start`
- `timeEnd = end`

Current reasoning:

- `detectedAt` is treated as the best observation start when present
- `start` remains the fallback because some events do not expose `detectedAt`

### Settled-event filter

- live HTTP ingest only normalizes events where `end` is present
- replay ingest from `--event-json` does not add that settled filter automatically

Current reasoning:

- the live ingest path is intended to pull only completed events for stable local rows
- fixture replay stays closer to its input so tests can exercise both settled and unsettled shapes explicitly

### Camera name resolution

Camera name precedence is:

1. explicit replay fallback from `--camera-name`
2. `camera.displayName`
3. `camera.name`
4. lookup by `cameraId`, string `camera`, or `camera.id` against `/cameras`

If none of those produce a usable name, the event is currently ignored.

`camera_id` is filled from the same lookup path used for camera resolution:

1. `cameraId`
2. string `camera`
3. `camera.id`

### Kind normalization

Kind selection is:

1. `smartDetectTypes` when present
2. direct `type` only for supported direct kinds

Current alias mapping:

- `car -> vehicle`
- `pet -> animal`

Current direct kinds:

- `person`
- `animal`
- `vehicle`
- `package`
- `licensePlate`
- `face`
- `car`
- `pet`
- `alrm*`

## Ignored Shapes

These event classes are currently ignored instead of inserted:

- events with no supported kind after normalization
- events with no usable event ID
- events with no usable `detectedAt` or `start`
- live events that have not settled yet because `end` is missing
- events with no resolvable camera name

`motion` currently falls into the ignored bucket because this package is storing normalized observation kinds, not every raw Protect event type.

## Snapshot Maintenance

The checked-in baseline is:

- `Tests/Fixtures/ProtectAPI/events-response.json`
- `Tests/Fixtures/ProtectAPI/cameras-response.json`
- `Tests/Fixtures/ProtectAPI/schema-snapshot.json`
- `Tests/Fixtures/ProtectAPIReal/events-response-protect-7.0.94.json`
- `Tests/Fixtures/ProtectAPIReal/cameras-response-protect-7.0.94.json`
- `Tests/Fixtures/ProtectAPIReal/schema-snapshot-protect-7.0.94.json`

`ProtectAPI` is the synthetic baseline used to preserve broad-shape coverage, including embedded camera objects and `cameraId`.

`ProtectAPIReal` is a sanitized controller capture used to document the currently observed live event-list shape. The committed filename includes the observed Protect version so fixture diffs are easier to track across upgrades.

Both fixture sets should stay small and representative.

When the Protect API changes:

1. capture or replay a new small sample
2. update the sanitized fixtures
3. regenerate the schema snapshot
4. inspect the diffs to see exactly which fields, types, or optionality changed

The `snapshotWriterProducesCommittedFixturesFromUnsanitizedSamples` test supports fixture regeneration when run with `REGENERATE_PROTECT_FIXTURES=1`.

## Deferred Identity Question

The schema does not yet include controller or source identity. That may matter later if one local database starts mixing multiple Protect controllers or other event sources, but the current repo is intentionally not guessing at that shape yet.
