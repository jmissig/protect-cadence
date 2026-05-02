# protect-cadence

`protect-cadence` is a small local-first CLI for turning UniFi Protect detections into a compact SQLite evidence store, then querying or modeling that evidence without talking to Protect again.

The product shape is intentionally narrow:

- one executable: `protect-cadence`
- one source-of-truth evidence database
- one optional derived model database
- one extraction-oriented query surface for operators, scripts, and local agents

It is not a dashboard, clip browser, or general Protect SDK.

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

To install the repo's OpenClaw skill separately:

```bash
make install-skill
```

## First Run

The normal first run is interactive:

```bash
protect-cadence ingest
```

On first run it will prompt for:

- Protect controller URL
- username and password
- whether to allow insecure TLS
- a local evidence database path
- whether to seed an initial recent window

Managed defaults remain:

- config: `~/Library/Application Support/protect-cadence/config.json`
- evidence DB: `~/Library/Application Support/protect-cadence/protect-cadence.sqlite`
- model DB: `~/Library/Application Support/protect-cadence/protect-cadence-model.sqlite`

If you only want to configure saved controller auth, use the canonical auth
command:

```bash
protect-cadence auth login
```

`protect-cadence setup` is a convenience alias for `auth login` so local tools
can share the same friendly entrypoint while keeping `auth` canonical.

After setup, the usual ingest path is:

```bash
protect-cadence ingest --last-hours 6
```

For tests, automation, and agent runs, prefer explicit paths:

```bash
protect-cadence ingest \
  --config /tmp/protect-config.json \
  --db /tmp/protect-cadence.sqlite \
  --last-hours 6
```

## What Lives Where

The code is organized around product seams rather than historical scaffolding:

- `Sources/ProtectCadence/Store`: evidence DB schema, migrations, and query surface
- `Sources/ProtectCadence/Protect`: Protect auth, controller boundary, normalization, ingest, validation, and snapshot helpers
- `Sources/ProtectCadence/Model`: derived modeling layer built from the evidence DB
- `Sources/ProtectCadence/CLI`: command definitions, routing, help, and output rendering
- `Tests/ProtectCadenceTests`: suites split by boundary instead of one catch-all test file

This is still one Swift module by design. The repo is small enough that explicit directories and files are clearer than adding SwiftPM target layering for its own sake.

## Command Surface

The public surface is one executable with a few command families:

```bash
protect-cadence ingest
protect-cadence query events
protect-cadence query summary
protect-cadence query compare
protect-cadence model rebuild
protect-cadence model episodes
protect-cadence model findings
protect-cadence annotations add
protect-cadence annotations list
protect-cadence annotations kinds
protect-cadence annotations targets
protect-cadence auth status
protect-cadence auth login
protect-cadence setup  # alias for auth login
protect-cadence validate
```

### Query Examples

```bash
protect-cadence query events --last-hours 24
protect-cadence query events --camera Driveway --kind person
protect-cadence query events --date 2026-03-25 --hour 08:00
protect-cadence query events --weekday --time-of-day 22:00-06:00

protect-cadence query summary --last-hours 24
protect-cadence query summary --group-by date --group-by kind
protect-cadence query summary --weekday --group-by weekday --group-by hour
protect-cadence query summary \
  --since "2026-03-25 00:00" \
  --until "2026-03-26 00:00" \
  --group-by weekday \
  --group-by hour \
  --group-by camera

protect-cadence query compare --last-hours 1 --vs-prior-window
protect-cadence query compare --last-hours 1 --vs-same-window-last-week
protect-cadence query compare \
  --since "2026-04-27 08:00" \
  --until "2026-04-27 10:00" \
  --vs-same-weekday-prior-weeks 4
protect-cadence query compare \
  --since 2026-03-27T00:00:00Z \
  --until 2026-03-28T00:00:00Z \
  --vs-same-window-yesterday \
  --group-by date \
  --group-by kind
```

Useful semantics:

- `query events` defaults to `--limit 50`
- `query summary` defaults to the last 24 hours unless `--date` is used without an explicit window
- `query compare` requires one primary window plus exactly one comparison mode
- `--vs-same-weekday-prior-weeks N` compares the primary window to each of the prior `N` matching local weekday windows separately; it does not aggregate them into a baseline
- `--day-of-week`, `--weekday`, `--weekend`, `--date`, `--hour`, and `--time-of-day` all apply in local machine time
- counts are normalized event-row counts first; distinct source Protect event counts are reported separately where relevant
- `query summary --group-by` can be repeated for descriptive distributions such as weekday/hour/camera within one window
- summaries return observed buckets only; `query compare` preserves zero-count peer buckets when one side of a comparison has activity; multi-peer comparisons preserve those buckets per peer window

### Read-Only Exploration

For Datasette-style inspection of the evidence/model SQLite databases, see [Docs/read-only-exploration.md](Docs/read-only-exploration.md). Use stable CLI verbs first for normal Robut/chat answers; use read-only SQL for source coverage, model debugging, and event → episode → finding traceability.

### JSON Output

Human-readable text is the default. Use JSON explicitly when an agent or script needs the full response shape:

```bash
protect-cadence query summary --last-hours 24 --format json
protect-cadence query compare --last-hours 1 --vs-prior-window --json
protect-cadence model findings --last-hours 24 --format json
protect-cadence validate --format json
```

`query summary` and `query compare` JSON responses include drill-down descriptors that point back to the matching `query events` slice.

### Annotations

Annotations are writable sidecar context, stored separately from the read-mostly evidence database. By default the sidecar path is a sibling of the evidence DB, such as `protect-cadence-annotations.sqlite`. Use `--annotations-db` to override it.

```bash
protect-cadence annotations kinds --format json
protect-cadence annotations targets --account default --format json
protect-cadence annotations add \
  --account default \
  --target-kind camera \
  --target-id name:Driveway \
  --body "Driveway detections during construction week are noisy; do not treat them as a new routine." \
  --source human
protect-cadence annotations list --target-kind camera --target-id name:Driveway --format json
```

Supported target kinds are `camera`, `event`, `episode`, `finding`, `zone`, `context`, and `window`. Prefer stable target IDs when they exist:

- `camera`: `id:<camera-id>` or `name:<camera-name>`
- `event`: `event_id:<protect-event-id>#kind:<kind>`
- `episode`: `run:<run-id>/episode:<episode-id>`
- `finding`: `run:<run-id>/finding:<finding-id>`
- `context`: handles such as `family-privacy` or `school-morning`
- `window`: explicit local conventions such as `window:school-morning` or a documented time range

Query/model outputs include matching annotations by default where they naturally encounter the target. Use `--no-annotations` on supported query/model commands to omit them.

## Protect Boundary

Live ingest supports either saved config or explicit overrides:

- `--controller-url`
- `--username`
- `--password`
- `--allow-insecure-tls`

Environment variables are also supported:

- `PROTECT_CONTROLLER_URL`
- `PROTECT_USERNAME`
- `PROTECT_PASSWORD`
- `PROTECT_ALLOW_INSECURE_TLS`

For replay or fixture-based verification:

```bash
protect-cadence ingest \
  --db /tmp/protect-cadence.sqlite \
  --event-json Tests/Fixtures/ProtectAPI/events-response.json \
  --camera-json Tests/Fixtures/ProtectAPI/cameras-response.json
```

## Derived Model Database

All imported Protect events are stored in the main evidence database. Any model outputs are derived from that data and can be rebuilt whenever needed.

Typical flow:

```bash
protect-cadence model rebuild
protect-cadence model findings --last-hours 24
protect-cadence model episodes --camera Driveway --since 2026-04-14T00:00:00Z
```

You can point both databases explicitly:

```bash
protect-cadence model rebuild \
  --db /path/to/protect-cadence.sqlite \
  --model-db /path/to/protect-cadence-model.sqlite
```

The current model surface exposes:

- deterministic detection episodes
- per-state time-bucket statistics
- state transition statistics
- descriptive attention findings such as `unexpected_presence`, `unexpected_transition`, and `unusual_duration`

This layer is still evidence-oriented. It does not decide what is anomalous for the household.

See [Docs/cadence-modeling-layer.md](Docs/cadence-modeling-layer.md) for the current modeling rules.

## Related Docs

- [Docs/protect-api-contract.md](Docs/protect-api-contract.md)
- [Docs/cadence-modeling-layer.md](Docs/cadence-modeling-layer.md)

For command help:

```bash
protect-cadence --help
protect-cadence ingest --help
protect-cadence query --help
protect-cadence model --help
protect-cadence auth --help
protect-cadence setup --help
protect-cadence validate --help
```

---

Made with Codex and OpenClaw.
