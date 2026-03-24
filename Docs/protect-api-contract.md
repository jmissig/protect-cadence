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

## Camera Fields Currently Consumed

- `id`
- `displayName`
- `name`

## Normalization Rules

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

Those fixtures are sanitized and intentionally small. They should stay representative of the event and camera shapes ingest relies on.

When the Protect API changes:

1. capture or replay a new small sample
2. update the sanitized fixtures
3. regenerate the schema snapshot
4. inspect the diffs to see exactly which fields, types, or optionality changed

The `snapshotWriterProducesCommittedFixturesFromUnsanitizedSamples` test supports fixture regeneration when run with `REGENERATE_PROTECT_FIXTURES=1`.
