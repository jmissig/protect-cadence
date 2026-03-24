# protect-cadence

`protect-cadence` is a small local-first pipeline for turning UniFi Protect detections into a compact SQLite dataset.

The current repo is still early, but it already supports:

- creating and migrating a local SQLite database
- normalizing one Protect event fixture into one or more event rows
- querying recent rows as JSON
- querying grouped activity summaries as JSON

It does not yet talk to a real Protect controller over HTTP. The ingest command is fixture-based for now.

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

### `protect-cadence-ingest`

Today this command has two modes:

- with no arguments, it initializes the database and returns a JSON status object
- with `--event-json`, it reads one Protect event payload from disk, normalizes it, and inserts deduplicated rows

Example:

```bash
swift run protect-cadence-ingest \
  --event-json ./fixtures/event.json \
  --camera-name "Driveway"
```

Notes:

- `--camera-name` is only needed when the payload does not already contain a usable camera name
- duplicate `(event_id, kind)` rows are ignored on insert
- output is JSON, intended for local tools and agents

### `protect-cadence-query recent`

Returns the newest normalized rows first.

Examples:

```bash
swift run protect-cadence-query recent
swift run protect-cadence-query recent --limit 10
swift run protect-cadence-query recent --limit 10 --last-hours 24
```

Behavior:

- default `--limit` is `50`
- `--last-hours` is optional for `recent`
- when `--last-hours` is provided, the response includes the effective query window

### `protect-cadence-query summary`

Returns grouped counts by camera and kind for a time window.

Examples:

```bash
swift run protect-cadence-query summary
swift run protect-cadence-query summary --last-hours 24
swift run protect-cadence-query summary --db ./data/protect-cadence.sqlite --last-hours 168
```

Behavior:

- default window is the last `24` hours
- `groups` contains flat `{ camera, kind, rowCount }` entries
- `totalRows` is the number of normalized rows in the window
- `distinctEventCount` counts unique `event_id` values so multi-kind events are not double-counted there

## Example Fixture

The ingest command expects one JSON object shaped like a Protect event payload. A minimal example:

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
swift run protect-cadence-ingest
```

2. Ingest one or more local event fixtures:

```bash
swift run protect-cadence-ingest --event-json ./fixtures/event-1.json
swift run protect-cadence-ingest --event-json ./fixtures/event-2.json
```

3. Inspect the latest rows:

```bash
swift run protect-cadence-query recent --limit 20
```

4. Ask for a compact summary:

```bash
swift run protect-cadence-query summary --last-hours 24
```

## Output Shape

All current commands default to JSON output.

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

## Current Limits

Current scope is intentionally narrow:

- no real Protect API client yet
- no compare mode yet
- no raw JSON archival yet
- no dashboard or UI

The next useful steps are to keep refining the query surface and then add a thin real Protect ingest boundary without turning the project into a broad Protect SDK.
