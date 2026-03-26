# protect-cadence

`protect-cadence` is a small local CLI for pulling UniFi Protect detections into a local SQLite database and querying them as compact JSON.

It is built around two normal tasks:

- ingest recent Protect events into SQLite
- query event rows or a short grouped summary

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
protect-cadence query events --day-of-week mon --day-of-week wed
protect-cadence query events --weekday
protect-cadence query events --weekend --time-of-day 22:00-06:00
protect-cadence query events --time-of-day 22:00-06:00

protect-cadence query summary
protect-cadence query summary --last-hours 24
protect-cadence query summary --since 2026-03-25T00:00:00Z --until 2026-03-26T00:00:00Z --group-by date
protect-cadence query summary --group-by date --group-by kind
protect-cadence query summary --weekday --group-by weekday --group-by hour
```

Notes:

- `query events` defaults to `--limit 50`
- `query summary` defaults to the last `24` hours
- `--since` and `--until` are the public explicit bounds
- `--since` alone resolves to a window ending at `now`
- `--until` requires `--since`
- `--day-of-week` is repeatable and uses local weekdays: `sun`, `mon`, `tue`, `wed`, `thu`, `fri`, `sat`
- `--weekday` expands to Monday through Friday
- `--weekend` expands to Saturday and Sunday
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

For full command help:

```bash
protect-cadence --help
protect-cadence ingest --help
protect-cadence query --help
protect-cadence auth --help
```

Made with Codex and OpenClaw.
