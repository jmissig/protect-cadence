# protect-cadence

`protect-cadence` is a small local-first pipeline for turning UniFi Protect detections into a compact SQLite dataset.

The current repo is still early, but it already supports:

- creating and migrating a local SQLite database
- bounded HTTP ingest from a local Protect controller
- normalizing one or more Protect event fixtures into event rows
- querying recent rows as JSON
- querying grouped activity summaries as JSON

The ingest path is still intentionally small: login, fetch recent settled events, normalize them, insert deduplicated rows, and optionally write sanitized API snapshots for tests.

Current project version: `0.9.0`.

This repo uses a single top-level `VERSION` file as its lightweight release marker. There is no separate metadata system yet.

## What It Stores

The project treats cameras as sensors, not as video sources.

Each normalized row currently stores:

- `time_start`
- `time_end`
- `camera_id`
- `camera`
- `event_type`
- `kind`
- `event_id`

One Protect event can become multiple rows if it contains multiple smart-detect kinds such as `person` and `vehicle`.

Field intent:

- `camera_id` keeps the stable Protect camera identifier when the payload exposes one
- `camera` remains the human-readable camera name used for inspection and grouping
- `event_type` preserves the original Protect event type such as `smartDetectZone` or `smartDetectLine`

The schema does not yet encode controller or source identity. If this repo starts ingesting multiple controllers, that may need an explicit schema decision later.

## Requirements

- macOS 13 or newer
- Swift 6.2+

## Build And Test

Recommended local workflow for this repo:

```bash
make build
make test
```

That keeps build products in a visible `build/` directory instead of SwiftPM's default hidden `.build/` path.

If you prefer raw SwiftPM commands, use:

```bash
swift build --build-path build
swift test --build-path build
```

Plain `swift build` still works, but SwiftPM will then use `.build/`.

## Install The Binary

There is now a small install target for local use:

```bash
make install
```

By default this installs the release binary to `~/bin/protect-cadence`.

Useful variants:

```bash
BINDIR="$HOME/.local/bin" make install
make release
make show-bin
```

If `~/bin` is not already on your `PATH`, add it before expecting `protect-cadence` to resolve globally.

## Database Location

By default, commands create or use a SQLite file named `protect-cadence.sqlite` in the current working directory.

You can override that with `--db /path/to/protect-cadence.sqlite`.

The interactive first-run `ingest` flow instead suggests a durable default under:

- `~/Library/Application Support/protect-cadence/protect-cadence.sqlite`

## Auth And Config

Live ingest uses this auth resolution order:

- explicit CLI flags
- environment variables
- `~/Library/Application Support/protect-cadence/config.json`

The config file stores:

- `auth.controllerURL`
- `auth.username`
- `auth.password`
- `auth.allowInsecureTLS`
- `ingest.databasePath`

The config file is written with `0600` permissions, and its parent directory is tightened to `0700`.

This keeps unattended local execution simple: one config file, no separate secret store, and no Keychain dependency.

Supported auth env vars remain:

- `PROTECT_CONTROLLER_URL`
- `PROTECT_USERNAME`
- `PROTECT_PASSWORD`
- `PROTECT_ALLOW_INSECURE_TLS`

Recommended first-time setup:

```bash
swift run protect-cadence ingest
```

## Current Commands

### `protect-cadence ingest`

This is the primary ingest entrypoint and has three modes:

- with no arguments, it runs an interactive first-run flow when saved auth or a saved database path is missing
- with `--last-hours <n>`, it logs into Protect, fetches a bounded event window, normalizes settled events, and inserts deduplicated rows
- with `--event-json`, it replays one event object or an array of event objects from disk

First-run behavior:

- collects auth if the config does not already have controller URL, username, password, and insecure TLS preference
- prompts for `allowInsecureTLS` unless it was supplied by `--allow-insecure-tls` or `PROTECT_ALLOW_INSECURE_TLS`
- prompts for a durable database path, defaulting to Application Support
- asks whether to seed the database immediately
- if you seed, asks how many recent hours to import, defaulting to `24`
- prints phase-oriented progress while the live ingest is running
- saves one config file and keeps the durable ingest config limited to `databasePath`

Live ingest example:

```bash
swift run protect-cadence ingest
swift run protect-cadence ingest --last-hours 6
```

Live ingest with explicit overrides:

```bash
swift run protect-cadence ingest \
  --last-hours 6 \
  --controller-url https://protect.local \
  --username local-user \
  --password local-password \
  --allow-insecure-tls
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
- live ingest also accepts `--config /path/to/config.json` if you do not want the default config path
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

Manages the default live-ingest credentials.

```bash
swift run protect-cadence auth
swift run protect-cadence auth status
swift run protect-cadence auth login
swift run protect-cadence auth clear
```

Behavior:

- `auth` with no subcommand behaves like `auth status`
- `auth login` accepts `--controller-url`, `--username`, `--password`, and `--allow-insecure-tls`
- `auth login` prompts for any missing controller URL or username, prompts for the password if it is not supplied by flag or env var, and prompts for insecure TLS unless it was supplied by flag or env var
- `auth login` stores the password in the config file
- `auth status` reports whether the config file exists and whether it currently includes a stored password
- `auth clear` removes the config file
- `auth clear --force` skips the confirmation prompt
- all auth subcommands accept `--config /path/to/config.json`

Current config file shape:

```json
{
  "auth": {
    "allowInsecureTLS": false,
    "controllerURL": "https://protect.local",
    "password": "local-password",
    "username": "local-user"
  },
  "ingest": {
    "databasePath": "/Users/example/Library/Application Support/protect-cadence/protect-cadence.sqlite"
  }
}
```

For unattended local runs, point cron or `launchd` at the same config path and avoid interactive secret sources.

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

1. Save live-ingest credentials:

```bash
swift run protect-cadence auth login
```

2. Run the first interactive setup:

```bash
swift run protect-cadence ingest
```

3. Ingest one or more local event fixtures:

```bash
swift run protect-cadence ingest --event-json ./fixtures/event-1.json
swift run protect-cadence ingest --event-json ./fixtures/event-2.json
```

4. Inspect the latest rows:

```bash
swift run protect-cadence query recent --limit 20
```

5. Ask for a compact summary:

```bash
swift run protect-cadence query summary --last-hours 24
```

6. Optionally capture sanitized API snapshots for regression tests:

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

Each event row includes `timeStart`, `timeEnd`, `cameraID`, `camera`, `eventType`, `kind`, and `eventID`.

`summary` returns:

- `command`
- `databasePath`
- `window`
- `totalRows`
- `distinctEventCount`
- `groups`

## Current Limits

Current scope is intentionally narrow:

- no websocket or realtime ingest
- no compare mode yet
- no raw JSON archival yet
- no dashboard or UI
- `auth login` stores credentials but does not perform a live validation request

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
