# protect-cadence

`protect-cadence` is a small local CLI for pulling UniFi Protect detections into a local SQLite database and querying them as compact JSON.

It is built around two normal tasks:

- ingest recent Protect events into SQLite
- query recent rows or a short grouped summary

## Install

Build and install the binary:

```bash
make install
```

That installs `protect-cadence` to `~/bin/protect-cadence` by default.

If you want a different install location:

```bash
BINDIR="$HOME/.local/bin" make install
```

If `~/bin` is not already on your `PATH`, add it first.

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

## Common Queries

Most people will use these:

```bash
protect-cadence query recent
protect-cadence query recent --limit 10
protect-cadence query recent --last-hours 24

protect-cadence query summary
protect-cadence query summary --last-hours 24
```

Notes:

- `query recent` defaults to `--limit 50`
- `query summary` defaults to the last `24` hours
- output is JSON

## Overrides

You can override the saved paths when needed:

```bash
protect-cadence ingest --config /path/to/config.json
protect-cadence query recent --db /path/to/protect-cadence.sqlite
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
