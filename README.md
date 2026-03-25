# protect-cadence

`protect-cadence` is a small local-first pipeline for turning UniFi Protect detections into a compact SQLite dataset.

The current repo is still early, but it already supports:

- creating and migrating a local SQLite database
- bounded HTTP ingest from a local Protect controller
- normalizing one or more Protect event fixtures into event rows
- querying recent rows as JSON
- querying grouped activity summaries as JSON

The ingest path is still intentionally small: login, fetch recent settled events, normalize them, insert deduplicated rows, and optionally write sanitized API snapshots for tests.

## What It Stores

The project treats cameras as sensors, not as video sources.

Each normalized row currently stores:

- `time_start`
- `time_end`
- `camera`
- `kind`
- `event_id`

One Protect event can become multiple rows if it contains multiple smart-detect kinds such as `person` and `vehicle`.

## Requirements

- macOS 13 or newer
- Swift 6.2+

## Build And Test

```bash
swift build
swift test
```

## Database Location

By default, commands create or use a SQLite file named `protect-cadence.sqlite` in the current working directory.

You can override that with `--db /path/to/protect-cadence.sqlite`.

## Current Commands

### `protect-cadence ingest`

This is the primary ingest entrypoint and has three modes:

- with no arguments, it initializes the database and returns a JSON status object
- with `--last-hours <n>`, it logs into Protect, fetches a bounded event window, normalizes settled events, and inserts deduplicated rows
- with `--event-json`, it replays one event object or an array of event objects from disk

Live ingest example:

```bash
export PROTECT_CONTROLLER_URL="https://protect.local"
export PROTECT_USERNAME="local-user"
export PROTECT_PASSWORD="local-password"

swift run protect-cadence ingest --last-hours 6
```

Replay example with event and camera snapshots:

```bash
swift run protect-cadence ingest \
  --event-json ./Tests/Fixtures/ProtectAPI/events-response.json \
  --camera-json ./Tests/Fixtures/ProtectAPI/cameras-response.json
```

Snapshot capture example:

```bash
swift run protect-cadence ingest \
  --last-hours 6 \
  --write-api-snapshot-dir ./tmp/protect-api-snapshot
```

Notes:

- `--camera-json` is optional, but useful when replaying endpoint snapshots where events only carry camera IDs
- `--camera-name` is only needed for replay fixtures that do not already contain a usable camera name and do not have a companion camera snapshot
- duplicate `(event_id, kind)` rows are ignored on insert
- live ingest counts ignored unsettled events and unsupported payloads in the JSON response
- output is JSON, intended for local tools and agents

### `protect-cadence query recent`

Returns the newest normalized rows first.

Examples:

```bash
swift run protect-cadence query recent
swift run protect-cadence query recent --limit 10
swift run protect-cadence query recent --limit 10 --last-hours 24
```

Behavior:

- default `--limit` is `50`
- `--last-hours` is optional for `recent`
- when `--last-hours` is provided, the response includes the effective query window

### `protect-cadence query summary`

Returns grouped counts by camera and kind for a time window.

Examples:

```bash
swift run protect-cadence query summary
swift run protect-cadence query summary --last-hours 24
swift run protect-cadence query summary --db ./data/protect-cadence.sqlite --last-hours 168
```

### `protect-cadence auth`

This is intentionally only a stub right now. It exists so the single-command surface is in place before auth grows into per-user config and Keychain-backed setup.

```bash
swift run protect-cadence auth
swift run protect-cadence auth status
```

Behavior:

- default window is the last `24` hours
- `groups` contains flat `{ camera, kind, rowCount }` entries
- `totalRows` is the number of normalized rows in the window
- `distinctEventCount` counts unique `event_id` values so multi-kind events are not double-counted there

## Example Fixture

The replay path accepts either one Protect event object or an array of event objects. A minimal single-event example:

```json
{
  "id": "event-123",
  "eventId": "event-123",
  "type": "smartDetectZone",
  "start": 1710000000000,
  "end": 1710000005000,
  "detectedAt": 1710000001000,
  "smartDetectTypes": ["person", "vehicle"],
  "camera": {
    "displayName": "Driveway"
  }
}
```

That fixture normalizes into two rows: one `person` row and one `vehicle` row.

## Typical Local Workflow

1. Initialize a database:

```bash
swift run protect-cadence ingest
```

2. Ingest one or more local event fixtures:

```bash
swift run protect-cadence ingest --event-json ./fixtures/event-1.json
swift run protect-cadence ingest --event-json ./fixtures/event-2.json
```

3. Inspect the latest rows:

```bash
swift run protect-cadence query recent --limit 20
```

4. Ask for a compact summary:

```bash
swift run protect-cadence query summary --last-hours 24
```

5. Optionally capture sanitized API snapshots for regression tests:

```bash
swift run protect-cadence ingest \
  --last-hours 1 \
  --write-api-snapshot-dir ./Tests/Fixtures/ProtectAPI
```

## Output Shape

All current commands default to JSON output.

`ingest` returns:

- `command`
- `databasePath`
- optional `window`
- `fetchedEventCount`
- `normalizedRowCount`
- `insertedRowCount`
- `ignoredEventCount`
- `status`

`recent` returns:

- `databasePath`
- optional `window`
- `events`

`summary` returns:

- `command`
- `databasePath`
- `window`
- `totalRows`
- `distinctEventCount`
- `groups`

## Compatibility Shims

`protect-cadence-ingest` and `protect-cadence-query` still exist as small compatibility wrappers, but the documented path is now the unified `protect-cadence` executable.

## Current Limits

Current scope is intentionally narrow:

- no websocket or realtime ingest
- no compare mode yet
- no raw JSON archival yet
- no dashboard or UI

## Protect API Contract

The current ingest-side Protect contract lives in:

- `Docs/protect-api-contract.md`
- `Tests/Fixtures/ProtectAPI/events-response.json`
- `Tests/Fixtures/ProtectAPI/cameras-response.json`
- `Tests/Fixtures/ProtectAPI/schema-snapshot.json`
- `Tests/Fixtures/ProtectAPIReal/events-response-protect-7.0.94.json`
- `Tests/Fixtures/ProtectAPIReal/cameras-response-protect-7.0.94.json`
- `Tests/Fixtures/ProtectAPIReal/schema-snapshot-protect-7.0.94.json`

`ProtectAPI` is the small synthetic baseline that exercises broader fixture shapes. `ProtectAPIReal` is a sanitized live controller capture, versioned in the filename by the observed Protect release. The schema snapshots are generated from the committed fixtures and exist to make drift obvious in diffs and tests.
