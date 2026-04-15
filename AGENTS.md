# AGENTS.md

## Purpose

`protect-cadence` is a small, local-first pipeline for turning UniFi Protect detections into a compact time-series dataset that can be queried cheaply and safely.

This project is not a camera app, not a dashboard, and not a general Protect client. Treat cameras as sensors. The useful output is structured observations and the ability to compare patterns over time.

## Current State

The repository is still early, but it is past the pure scaffold stage.

Today it contains:
- a Swift Package Manager package
- two executable targets: `protect-cadence-ingest` and `protect-cadence-query`
- a small shared core module
- a local SQLite database layer with migrations
- bounded HTTP ingest from a real Protect controller
- fixture replay plus sanitized API snapshot capture for tests
- a small query surface for recent rows and grouped summaries
- a checked-in ingest-side Protect API contract snapshot

The ingest path is now real enough to validate against controllers. The query surface is still provisional and should stay easy to reshape while the useful extraction patterns become clearer.

When adding structure, prefer the smallest step that moves the project toward the intended CLI and storage model. Do not introduce architecture meant for hypothetical future scale.

## Primary Goals

The system should make it easy for local tools and agents to pull out the observations needed to answer questions like:
- what changed today?
- when are animals usually detected?
- what detections happened in this camera during this part of the day?
- how does activity compare across time windows?

The system should produce:
- compact normalized event rows
- durable local storage
- small extraction-oriented query surfaces for local tools and agents
- outputs that make downstream reasoning easy without embedding that reasoning in the CLI itself
- a stable enough query grammar that agents can reliably ask for slices, aggregates, and comparisons

## Non-Goals

Avoid building:
- a UI
- live video access for agents
- clip browsing or thumbnails
- websocket streaming in v1
- a broad Protect SDK or full Protect mirror
- a complex daemon or service before there is clear need
- anomaly scoring, behavioral judgments, or other embedded reasoning in the CLI

Reasoning about whether something is notable, strange, or contextually unusual belongs in OpenClaw or another downstream consumer, not in this package.

## Architectural Direction

Preferred initial flow:

```text
UniFi Protect API
    -> protect-cadence-ingest
    -> SQLite
    -> protect-cadence-query
    -> local agent / OpenClaw
```

Optional sidecar:

```text
Protect events -> JSONL raw archive
```

OpenClaw and other local consumers should query the local dataset, not Protect directly.

The package should behave like a small local event warehouse with a narrow extraction CLI. It should expose clean slices of observation data; downstream tools can do the interpretation.

## Technology Preferences

- Language: Swift
- Package model: Swift Package Manager
- Primary store: SQLite
- SQLite wrapper: GRDB, used lightly

Apple-authored Swift packages are perfectly acceptable here when they materially simplify the implementation without turning the project into a framework-heavy system. Recommending packages such as `swift-argument-parser` is fine when they reduce custom plumbing and keep the CLI legible.

`apple/swift-log` is a reasonable package to consider if the CLI starts benefiting from clearer structured stderr logging, but it is not a default dependency. Add it only when the concrete logging need is clear.

Use GRDB for:
- database opening
- migrations
- parameterized queries
- straightforward row decoding

Avoid:
- elaborate ORM patterns
- deep protocol layering
- abstraction that hides SQL shape
- framework-heavy designs

## Design Principles

### Observations over surveillance

Do not optimize around direct video access. Optimize around normalized observations such as:
- person detected
- animal detected
- vehicle detected
- timestamp
- camera

### Patterns over raw events

Raw detections are not the product. The product is the ability to summarize, compare, and spot changes across time windows.

### Local, legible, replaceable

Prefer:
- explicit files
- explicit SQL
- narrow CLIs
- schemas that are easy to inspect by hand
- integrations with thin boundaries

Avoid:
- hidden state
- magical background behavior
- opaque abstractions
- large dependency surfaces tied to Protect

### Simplicity over cleverness

Before adding structure, ask:
1. Can this be solved with a smaller schema?
2. Can this be solved with a simple SQL query?
3. Can this be solved with a narrow CLI command?
4. Is this a real question worth supporting?
5. Does this increase clarity or only complexity?

If uncertain, choose the simpler design.

## Data Model Guidance

Start deliberately small.

Minimal event fields:
- `time_start`
- `time_end` when available
- `camera`
- `kind`
- `event_id`

Optional:
- `raw_json` for debugging or trust
- `zone` later, only if clearly useful
- stable camera identifiers if name-based handling proves too fragile

Do not:
- ingest broad device metadata into the main event table
- mirror every Protect field
- expand the schema casually
- store LLM-derived interpretations in the base event table

Suggested initial schema:

```sql
CREATE TABLE events (
  id INTEGER PRIMARY KEY,
  time_start TEXT NOT NULL,
  time_end TEXT,
  camera TEXT NOT NULL,
  kind TEXT NOT NULL,
  event_id TEXT NOT NULL,
  UNIQUE(event_id, kind)
);
```

One Protect event may normalize into multiple rows when Protect reports multiple kinds. The dedupe strategy should be explicit about that shape.

If schema pressure grows quickly, stop and reconsider the model before adding columns.

## Time Zone Policy

`protect-cadence` should treat event timestamps primarily as instants, then apply local-time interpretation where human-oriented slicing needs it.

Preferred policy:
- store event timestamps as absolute times in SQLite
- use local machine time when evaluating human-time groupings and filters such as:
  - `weekday`
  - `date`
  - `hour`
  - `time-of-day`
- accept explicit ISO 8601 bounds for `--since` / `--until`
- keep comparison/query semantics clear about bounds, but do not overcomplicate the schema with separate local-wall-clock provenance fields unless a real need appears

Rationale:
- for camera detections, the important fact is usually that an event happened at a particular moment
- downstream queries often need local household views like “weekday mornings” or “after 22:00”, so local-time interpretation belongs in the query layer
- unlike `clime`, this project does not need to preserve the exact emitted timestamp string plus offset as a first-class artifact of record

## Testing and operator-safety rules

For this repo, prefer repo-local or explicitly sandboxed verification.

- Do not treat the globally installed `protect-cadence` binary as the test target.
- Do not run `make install` or other install/publish steps as part of routine verification.
- Do not rely on ambient default config or database paths for tests.
- Prefer explicit `--db`, `--model-db`, and `--config` paths, ideally temp files, fixtures, or other repo-scoped scratch locations.
- Assume the default configured database may be shared with another human or process.
- If checking default-path behavior intentionally, treat that as a narrow compatibility test, not the normal smoke-test path.

Rationale:
- this project may have multiple real users on the same machine
- the default configured database location may be intentionally readable but not writable by this agent
- repo validation should avoid mutating shared operator state

## CLI Direction

The CLI is the main user and agent interface.

Current commands:
- `protect-cadence-ingest`
- `protect-cadence-query recent`
- `protect-cadence-query summary`

Likely next query direction:
- keep the command set small
- evolve toward a shared query grammar rather than many bespoke subcommands
- support filtered event slices, bucketed summaries, and later carefully-scoped comparisons

Useful query primitives:
- row slices filtered by time window, camera, and kind
- time-of-day filtering, including overnight ranges
- grouped counts by dimensions such as camera, kind, date, hour-of-day, or day-of-week
- explicit count semantics when row counts and distinct-event counts differ
- delta/comparison outputs only when they remain descriptive rather than interpretive
- optional later baseline-style outputs only if they stay mathematical and evidence-oriented

Output guidance:
- default to compact output
- prefer structured JSON for agent consumption
- avoid dumping raw payloads unless explicitly requested
- optimize for extracting relevant observations rather than narrating conclusions
- include the effective filters and counting semantics in the response shape

The CLI should help OpenClaw pull the right evidence quickly. It should not decide by itself whether a pattern is unusual, normal, or meaningful.

## Integration Guidance

Prefer direct UniFi Protect API access over large third-party abstractions. Authentication and API plumbing may be annoying, but keep that pain isolated to a thin boundary that can be replaced later.

The rest of the system should not care much about Protect-specific details once events have been normalized.

## Implementation Priorities

Near-term sequence:
1. validate the real bounded ingest path against actual controller data
2. confirm deduplication semantics for split multi-kind events
3. add a shared filter grammar across query commands
4. add extraction-oriented filters for kind, camera, and time-of-day
5. add richer grouped summaries and bucketing only where they answer real questions cleanly
6. add `compare` only after the core path is clean
7. consider baseline-style descriptive outputs only if they stay simple and obviously useful

Do not add calendar joins, weather joins, automation, or higher-level reasoning until the event dataset and extraction CLI are already useful on their own.

## Working Style For Contributors And Agents

- Challenge assumptions when the design starts drifting larger than the problem.
- Prefer trade-off analysis over generic best-practice language.
- Keep code and schemas easy to inspect after time away.
- Preserve replaceability at the Protect boundary.
- Keep outputs concise and useful.
- Do not invent future requirements without evidence.

Success looks like a small system that answers real questions well.

Failure signals:
- the schema expands rapidly without clear payoff
- the CLI starts mirroring the Protect API
- raw payloads become the default output
- the project becomes more about plumbing than evidence extraction
- the query surface fragments into one-off bespoke commands instead of a coherent filter/grouping model
- reasoning or anomaly judgments start creeping into the CLI surface

## Final Rule

Build a small, quiet, legible observation pipeline.

Do not build a platform.
