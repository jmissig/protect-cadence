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
- fixture-based event normalization and ingest
- a small query surface for recent rows and grouped summaries
- no real Protect HTTP integration yet

The CLI surface is still provisional and should stay easy to reshape while the real query needs become clearer.

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

## CLI Direction

The CLI is the main user and agent interface.

Expected first commands:
- `protect-cadence-ingest`
- `protect-cadence-query recent`
- `protect-cadence-query summary`
- `protect-cadence-query compare`
- extraction-oriented filters such as time-of-day, kind, and camera constraints

Output guidance:
- default to compact output
- prefer structured JSON for agent consumption
- avoid dumping raw payloads unless explicitly requested
- optimize for extracting relevant observations rather than narrating conclusions

Useful outputs include:
- recent normalized rows
- grouped counts
- time-window summaries
- filtered event slices
- delta/comparison results

The CLI should help OpenClaw pull the right evidence quickly. It should not decide by itself whether a pattern is unusual, normal, or meaningful.

## Integration Guidance

Prefer direct UniFi Protect API access over large third-party abstractions. Authentication and API plumbing may be annoying, but keep that pain isolated to a thin boundary that can be replaced later.

The rest of the system should not care much about Protect-specific details once events have been normalized.

## Implementation Priorities

Near-term sequence:
1. keep the package layout for multiple executables small and stable
2. add real Protect HTTP ingest with bounded fetch windows
3. confirm deduplication semantics for split multi-kind events
4. implement `recent`
5. implement `summary`
6. add extraction-oriented filters for kind, camera, and time-of-day
7. add `compare` only after the core path is clean

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
- reasoning or anomaly judgments start creeping into the CLI surface

## Final Rule

Build a small, quiet, legible observation pipeline.

Do not build a platform.
