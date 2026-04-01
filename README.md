# protect-cadence

`protect-cadence` is a small local CLI for pulling UniFi Protect detections into a local SQLite database and querying them as compact JSON.

It is built around two normal tasks:

- ingest recent Protect events into SQLite
- query events, grouped summaries, or window-to-window comparisons

## Install

Build and install the binary:

```bash
make install
```

That installs `protect-cadence` to `~/bin/protect-cadence` by default.

If `~/bin` is not already on your `PATH`, add it first.

If you want a different install location:

```bash
sudo make install PREFIX="/usr/local"
```

## First Run

The normal path is interactive:

```bash
protect-cadence ingest
```

On first run it will:

- prompt for your Protect controller URL, username, and password
- ask whether to allow insecure TLS
- prompt for a database path
- optionally import a recent window immediately

The default managed paths are:

- config: `~/Library/Application Support/protect-cadence/config.json`
- database: `~/Library/Application Support/protect-cadence/protect-cadence.sqlite`

After setup, the usual ingest command is:

```bash
protect-cadence ingest --last-hours 6
```

This is designed to be run regularly via launchd or cron. Time overlap is fine.

## Config Shape

The config file stores auth plus a top-level `databasePath`:

```json
{
  "auth": {
    "allowInsecureTLS": false,
    "controllerURL": "https://protect.local",
    "password": "local-password",
    "username": "local-user"
  },
  "databasePath": "/Users/example/Library/Application Support/protect-cadence/protect-cadence.sqlite"
}
```

The `query` command only needs the `databasePath` to function.

## Common Queries

Most people will use these:

```bash
protect-cadence query events
protect-cadence query events --limit 10
protect-cadence query events --last-hours 24
protect-cadence query events --since 2026-03-25T00:00:00Z
protect-cadence query events --since 2026-03-25T00:00:00Z --until 2026-03-26T00:00:00Z
protect-cadence query events --camera Driveway --kind person
protect-cadence query events --date 2026-03-25 --hour 08:00
protect-cadence query events --day-of-week mon --day-of-week wed
protect-cadence query events --weekday
protect-cadence query events --weekend --time-of-day 22:00-06:00
protect-cadence query events --time-of-day 22:00-06:00

protect-cadence query summary
protect-cadence query summary --last-hours 24
protect-cadence query summary --since 2026-03-25T00:00:00Z --until 2026-03-26T00:00:00Z --group-by date
protect-cadence query summary --group-by date --group-by kind
protect-cadence query summary --weekday --group-by weekday --group-by hour

protect-cadence query compare --last-hours 1 --vs-same-window-yesterday
protect-cadence query compare --last-hours 1 --vs-same-window-last-week
protect-cadence query compare --last-hours 1 --vs-prior-window
protect-cadence query compare --since 2026-03-27 08:00 --until 2026-03-27 09:00 --vs-since 2026-03-26 08:00 --vs-until 2026-03-26 09:00
protect-cadence query compare --since 2026-03-27 08:00 --until 2026-03-27 09:00 --vs-same-window-last-week
protect-cadence query compare --since 2026-03-27 08:00 --until 2026-03-27 09:00 --vs-window-before 2026-03-20 09:00
protect-cadence query compare --since 2026-03-20 08:00 --until 2026-03-20 09:00 --vs-window-after 2026-03-27 08:00
protect-cadence query compare --since 2026-03-27T00:00:00Z --until 2026-03-28T00:00:00Z --vs-same-window-yesterday --group-by date --group-by kind
```

Notes:

- `query events` defaults to `--limit 50`
- `query summary` defaults to the last `24` hours
- `query compare` requires a primary window via `--last-hours` or `--since`/`--until`
- `query compare` supports exactly one compare mode: an explicit comparison window via `--vs-since` + `--vs-until`, `--vs-same-window-yesterday`, `--vs-same-window-last-week`, `--vs-window-before`, `--vs-window-after`, or `--vs-prior-window`
- `--since` and `--until` are the public explicit bounds
- `--since` alone resolves to a window ending at `now`
- `--until` requires `--since`
- `--day-of-week` is repeatable and uses local weekdays: `sun`, `mon`, `tue`, `wed`, `thu`, `fri`, `sat`
- `--weekday` expands to Monday through Friday
- `--weekend` expands to Saturday and Sunday
- `--date` applies an exact local calendar-date bucket inside the selected window
- `--hour` applies an exact local hour bucket inside the selected window
- counts treat each normalized cadence event as one event
- `query summary` includes `eventCount` plus `sourceEventCount` provenance based on distinct Protect `event_id`
- `query summary` groups now include a `drillDown` descriptor that points back to the matching `events` slice
- `query compare` reports those same counts for both windows plus simple deltas
- `query compare` groups now include `windowDrillDown` and `comparisonWindowDrillDown` descriptors for both bucket slices
- output is JSON

## Overrides

You can override the saved paths when needed:

```bash
protect-cadence ingest --config /path/to/config.json
protect-cadence query events --db /path/to/protect-cadence.sqlite
```

Live ingest auth can also be overridden with flags or environment variables:

- `--controller-url`, `--username`, `--password`, `--allow-insecure-tls`
- `PROTECT_CONTROLLER_URL`, `PROTECT_USERNAME`, `PROTECT_PASSWORD`, `PROTECT_ALLOW_INSECURE_TLS`

If you want to manage saved auth directly:

```bash
protect-cadence auth status
protect-cadence auth login
protect-cadence auth clear
```

To validate live ingest assumptions against a current controller sample without writing to SQLite:

```bash
protect-cadence validate
protect-cadence validate --last-hours 12 --sample-limit 20
protect-cadence validate --last-hours 6 --write-api-snapshot-dir /tmp/protect-sample
```

`validate` reuses the same saved auth and override flags as live ingest, fetches a bounded recent sample, and returns JSON covering:

- whether `timeStart = detectedAt ?? start` still matches recent event shapes
- how many recent events are settled under `end != nil`
- whether normalized settled rows collide under the current `source event id + kind` dedupe key
- compact example rows for manual inspection

If `--write-api-snapshot-dir` is provided, the fetched sample is also written through the existing sanitizer/snapshot helper.

For full command help:

```bash
protect-cadence --help
protect-cadence ingest --help
protect-cadence validate --help
protect-cadence query --help
protect-cadence auth --help
```

Made with Codex and OpenClaw.
