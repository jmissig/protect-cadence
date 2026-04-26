# AGENTS.md

This file gives coding agents the durable context they need to work safely and consistently in this repository.

Preserve `protect-cadence`’s purpose. Do not broaden scope or invent a platform unless Julian explicitly asks.

## Project posture

Current posture: **in use**

`protect-cadence` is a working local-first CLI and OpenClaw-facing evidence tool. Prefer careful evolution over churn, but do not preserve stale paths out of inertia.

Project posture controls how aggressive architecture, schema, dependency, and cleanup changes should be.

- **In use** — prefer careful evolution. Debate sweeping architecture, schema, dependency, or command-surface changes before making them; if accepted, commit fully, document migration steps, and remove old paths cleanly.
- Prefer current recommended patterns and tools over preserving old approaches.
- Backwards compatibility is not a default goal unless this file, `README.md`, or a specific operator workflow says it is.

Underlying philosophy: **software is ephemeral**. Old code should earn its keep. Keep the tool alive by letting it change deliberately.

## Project brief

`protect-cadence` is a small local-first CLI for turning UniFi Protect detections into a compact SQLite evidence store, then querying or modeling that evidence without talking to Protect again.

This project is:
- a local event/observation pipeline for UniFi Protect detections
- a Swift Package Manager project with one `ProtectCadence` module and one `protect-cadence` executable
- a compact evidence store plus optional derived model database
- an extraction-oriented CLI for operators, scripts, and local agents
- a way for OpenClaw/Robut to reason about household camera activity from structured observations instead of live camera/video access

The useful output is structured observation data and evidence-bounded comparisons over time:
- what changed today?
- when are animals usually detected?
- what detections happened in this camera during this part of the day?
- how does activity compare across time windows?

Source of truth:
- Canonical evidence: the local `protect-cadence` SQLite evidence database built from normalized Protect event rows
- Derived/cached data: optional model database, deterministic episodes, bucket statistics, transition statistics, attention findings, fixture snapshots, and query summaries
- API contract docs: `Docs/protect-api-contract.md`
- Modeling rules: `Docs/cadence-modeling-layer.md`
- Human-facing usage guide: `README.md`
- Active backlog: `TODO.md`
- OpenClaw tool skill: `skills/protect-cadence/SKILL.md`

Never write to:
- ambient/default operator databases during routine verification
- shared configured databases that another human or process may be using
- installed binaries or installed OpenClaw skills during routine tests
- UniFi Protect controller state beyond bounded read-only API access and login/session handling
- model or evidence databases outside repo-local/temp/explicit paths unless Julian explicitly asks

Non-goals / anti-goals:
- not a camera app
- not a dashboard
- not a clip browser or thumbnail tool
- not a live video access layer for agents
- not a general UniFi Protect SDK or full Protect mirror
- not websocket streaming in v1
- not a complex daemon/service before there is clear need
- not an anomaly scorer or behavioral-judgment engine; the CLI exposes evidence and downstream tools interpret it

## Current state

Current stack:
- Swift 6.2 package targeting macOS 13+
- `ProtectCadence` library target
- `protect-cadence` executable target
- `ProtectCadenceTests` test target
- `swift-argument-parser` for CLI parsing
- GRDB for SQLite access
- `Makefile` wrappers for build/test/install/version sync

Current command surface:
- `protect-cadence ingest`
- `protect-cadence query events`
- `protect-cadence query summary`
- `protect-cadence query compare`
- `protect-cadence model rebuild`
- `protect-cadence model episodes`
- `protect-cadence model findings`
- `protect-cadence auth status`
- `protect-cadence validate`

Current source layout:
- `Sources/ProtectCadence/Store`: evidence DB schema, migrations, query surface, JSON output
- `Sources/ProtectCadence/Protect`: Protect auth, controller API boundary, normalization, ingest, validation, and sanitized snapshot helpers
- `Sources/ProtectCadence/Model`: derived modeling layer built from the evidence DB
- `Sources/ProtectCadence/CLI`: command routing, help, and shared CLI behavior
- `Sources/protect-cadence`: executable entry point
- `Tests/ProtectCadenceTests`: tests split by product boundary
- `Docs/`: API contract and modeling-layer docs

This is intentionally still one Swift module. The repo is small enough that explicit directories and files are clearer than SwiftPM target layering for its own sake.

## Validation

Routine checks:

```bash
make build
make test
```

Direct Swift equivalents:

```bash
swift build --build-path build --product protect-cadence
swift test --build-path build
```

Repo-local executable path after `make build`:

```bash
./build/debug/protect-cadence
```

Do not run during routine verification:
- `make install`
- `make install-skill`
- commands that mutate ambient/default operator config or database paths
- commands that write to installed binaries or installed OpenClaw skill directories
- destructive cleanup of evidence/model databases outside repo-local/temp/fixture paths

Use repo-local, fixture, sandboxed, or temporary paths for tests and smoke checks.

Prefer explicit paths:
- `--db`
- `--model-db`
- `--config`

Assume the default configured database may be shared with another human or process.

If checking default-path behavior intentionally, treat it as a narrow compatibility test, not the normal smoke-test path.

## Core principles

- Keep the project narrow and purpose-built.
- Treat cameras as sensors, not as media surfaces.
- Optimize around normalized observations, not live video access.
- Prefer compact local evidence over dashboards or surveillance features.
- Prefer clarity over cleverness.
- Prefer explicit files, explicit SQL, narrow CLIs, and schemas that are easy to inspect by hand.
- Keep integrations behind thin, replaceable boundaries.
- Keep command shapes coherent across subcommands.
- Let OpenClaw or downstream agents judge whether patterns are notable; the CLI should expose evidence.
- Avoid hidden state, magical background behavior, opaque abstractions, and broad dependency surfaces tied to Protect.
- Do not introduce architecture meant for hypothetical future scale.

## Architecture guidance

Preferred high-level flow:

```text
UniFi Protect API
    -> protect-cadence ingest
    -> SQLite evidence database
    -> protect-cadence query / model
    -> local agent / OpenClaw
```

Optional sidecar/archive:

```text
Protect events -> sanitized JSONL/API snapshots for fixtures or debugging
```

Rules:
- OpenClaw and other local consumers should query the local dataset, not Protect directly.
- Separate Protect API access, normalization, storage, query/model logic, and CLI presentation.
- Keep Protect-specific payload details inside the `Protect` boundary after normalization.
- Keep SQL and schema changes explicit and inspectable.
- Prefer simple SQL and indexes before adding columns or derived tables.
- Do not mirror every Protect field.
- Do not store LLM-derived interpretations in the base evidence table.
- After a directional change, make the new path the real path. Delete or clearly retire superseded code, docs, files, TODOs, and stale architectural discussion unless needed for migration or recovery.

## Tool and dependency posture

Preferred stack unless a strong reason appears otherwise:
- Swift
- Swift Package Manager
- `swift-argument-parser`
- SQLite
- GRDB, used lightly
- `Makefile` wrappers for common commands

Apple-authored Swift packages are acceptable when they materially simplify implementation without turning the project into a framework-heavy system.

`apple/swift-log` is reasonable to consider if the CLI starts benefiting from clearer structured stderr logging, but it is not a default dependency. Add it only when the concrete logging need is clear.

Use GRDB for:
- database opening
- migrations
- parameterized queries
- straightforward row decoding

Avoid:
- elaborate ORM patterns
- deep protocol layering without a concrete seam
- abstraction that hides SQL shape
- large dependency surfaces for a small local tool
- framework-heavy designs
- clever async/background architecture without a concrete need

For major architecture choices — persistence, ingest, query grammar, output formats, modeling, auth, testing — do a quick current tool/library scan before inventing custom infrastructure.

## Data and persistence

### Evidence database

The evidence database is the canonical local source of truth after ingest.

Minimal base event fields:
- `time_start`
- `time_end` when available
- `camera`
- `kind`
- `event_id`

Optional / bounded fields:
- `raw_json` only for debugging or trust when clearly useful
- `zone` later, only if clearly useful
- stable camera identifiers if name-based handling proves too fragile

Do not:
- ingest broad device metadata into the main event table
- mirror every Protect field
- expand the schema casually
- store LLM-derived interpretations in the base event table

One Protect event may normalize into multiple rows when Protect reports multiple kinds. Dedupe strategy must stay explicit about that shape.

If schema pressure grows quickly, stop and reconsider the model before adding columns.

### Derived model database

The model database is derived and rebuildable from the evidence database.

Current model surface exposes:
- deterministic detection episodes
- per-state time-bucket statistics
- state transition statistics
- descriptive attention findings such as `unexpected_presence`, `unexpected_transition`, and `unusual_duration`

This layer is still evidence-oriented. It does not decide what is anomalous for the household.

Keep the model DB rebuild-only until there is real operator pressure for incremental refresh.

### Time zone policy

Treat event timestamps primarily as instants, then apply local-time interpretation where human-oriented slicing needs it.

Preferred policy:
- store event timestamps as absolute times in SQLite
- use local machine time for human-time groupings and filters such as `weekday`, `date`, `hour`, and `time-of-day`
- accept explicit ISO 8601 bounds for `--since` / `--until`
- keep comparison/query semantics clear about bounds
- do not overcomplicate the schema with separate local-wall-clock provenance fields unless a real need appears

## CLI / local tool guidance

The CLI is the main user and agent interface.

It should feel like Julian’s other local-first CLIs:
- small command surface
- explicit local store/source boundaries
- compact human output by default
- structured output for agents and scripts
- narrow extraction-oriented commands
- clear diagnostic / validation commands

Preferred command families:
- `ingest`
- `query`
- `model`
- `auth`
- `validate`

Likely query direction:
- keep the command set small
- evolve toward a shared query grammar rather than many bespoke subcommands
- support filtered event slices, bucketed summaries, and carefully scoped comparisons

Useful query primitives:
- row slices filtered by time window, camera, and kind
- time-of-day filtering, including overnight ranges
- grouped counts by dimensions such as camera, kind, date, hour-of-day, or day-of-week
- explicit count semantics when row counts and distinct-event counts differ
- delta/comparison outputs only when they remain descriptive rather than interpretive
- baseline-style outputs only if they stay mathematical and evidence-oriented

Output guidance:
- default to compact human-readable output for operators
- use `--format json` for agent and script consumption
- `--json` is acceptable shorthand, but prefer `--format json` in guidance and examples
- include effective filters and counting semantics in JSON when relevant
- avoid dumping raw payloads unless explicitly requested
- avoid narrating conclusions; return evidence and let the caller interpret it

`validate` is an operator and agent-facing verification tool. It should fetch a bounded recent sample without writing to the evidence DB and summarize current controller assumptions. Useful checks include:
- how `timeStart` is chosen from live payloads
- how many events are settled versus open
- whether the current dedupe key collides on recent data
- compact examples for manual inspection

If `--write-api-snapshot-dir` is supplied, the sample should be sanitized and written through the same fixture snapshot helper used by tests.

## Protect boundary

Prefer direct UniFi Protect API access over large third-party abstractions.

Authentication and API plumbing may be annoying, but keep that pain isolated to a thin boundary that can be replaced later.

The rest of the system should not care much about Protect-specific details once events have been normalized.

Live ingest supports either saved config or explicit overrides:
- `--controller-url`
- `--username`
- `--password`
- `--allow-insecure-tls`

Environment variables:
- `PROTECT_CONTROLLER_URL`
- `PROTECT_USERNAME`
- `PROTECT_PASSWORD`
- `PROTECT_ALLOW_INSECURE_TLS`

Fixture/replay verification should use explicit paths and checked-in fixture payloads.

License/context note:
- Prior review found no need to pull in `unifi-protect` licensing for `protect-cadence` based on API-shape overlap alone.
- Keep Protect API code independently structured; do not copy third-party client structure or implementation.

## Layering rules

- CLI commands should parse options and call services; they should not own Protect payload details or SQL details.
- Protect adapters normalize raw API payloads at the boundary.
- Store/query code owns evidence schema, migrations, SQL, and counting semantics.
- Model code owns derived episodes/statistics/findings and treats the evidence DB as input.
- Feature code should not scatter migration, repair, or dedupe policy when a centralized store/ingest boundary exists.
- If malformed source or store state appears, prefer clear diagnostics and validation output over silent magical repair.
- Keep business/query/model logic testable without live Protect access, ambient config, default DB paths, or network side effects.

## Testing and verification

Use the documented validation commands before declaring success. If they are missing or stale, update them as part of the work.

Prefer tests for:
- Protect payload decoding and normalization
- source API contract assumptions
- fixture replay
- evidence database schema/migrations
- dedupe semantics, especially split multi-kind events
- query filters and grouping semantics
- count semantics: normalized event rows vs distinct source Protect events
- comparison window semantics
- model rebuild/episodes/findings behavior
- output format contracts: human/JSON where applicable
- config/path selection and repo-local safety
- data-loss or accidental-default-write regressions

Testing rules:
- Prefer repo-local or explicitly sandboxed verification.
- Prefer explicit `--db`, `--model-db`, and `--config` paths pointing at temp files, fixtures, or repo-scoped scratch locations.
- Do not mutate ambient/default operator state during routine verification.
- Do not treat the globally installed `protect-cadence` binary as the test target.
- Do not require live Protect controller access in normal tests.
- Do not install or publish as part of normal validation unless explicitly asked.
- Keep tests seam-focused and deterministic.
- Keep checked-in fixtures intentionally small so diffs stay legible.

## Failure signals

Agents should add or refine this section over time when the project reveals what bad drift looks like.

Watch for:
- the schema expands rapidly without clear payoff
- the CLI starts mirroring the Protect API
- raw payloads become the default output
- the project becomes more about API plumbing than evidence extraction
- the query surface fragments into bespoke one-off commands instead of a coherent filter/grouping model
- reasoning or anomaly judgments creep into the CLI surface
- model findings become opaque or non-rebuildable
- default config/database paths are used in routine verification
- install commands run during routine tests
- `AGENTS.md` becomes a backlog or philosophy dump instead of durable operating guidance

## Documentation and project hygiene

Use this docs split:
- `README.md` — human-facing usage guide: install, first run, command examples, Protect boundary, model usage
- `TODO.md` — active backlog / near-term parking lot, not a philosophy dump
- `AGENTS.md` — durable architecture, constraints, source-of-truth boundaries, project posture, validation, and agent guidance
- `Docs/protect-api-contract.md` — Protect API contract assumptions and snapshot notes
- `Docs/cadence-modeling-layer.md` — derived model semantics and current modeling rules
- `skills/protect-cadence/SKILL.md` — OpenClaw skill instructions for using the installed tool

Completed work should leave `TODO.md` and live in git history, tests, code, and release notes if relevant.

When architecture choices change, update a decision section or relevant docs with:
- date
- decision
- alternatives considered
- rationale
- migration impact

If unresolved, mark it as `OPEN` with the next checkpoint.

## When to update AGENTS.md

Update this file when agent behavior should change in future sessions.

Good reasons to update it:
- project posture changes
- validation commands change
- source-of-truth boundaries change
- a durable architecture or schema decision changes
- a recurring agent mistake needs a guardrail
- a new failure signal becomes clear
- a project-specific constraint would otherwise need to be repeated in prompts

Agents may update `AGENTS.md` proactively for small durable guardrails, corrected validation commands, clarified source-of-truth boundaries, or newly obvious failure signals.

Agents should propose or confirm before making larger changes to project philosophy, posture, architecture direction, or scope boundaries.

Do not use `AGENTS.md` as a changelog or scratchpad. Keep it concise, durable, and action-guiding.

## Working style for contributors and agents

- Start by reading `AGENTS.md`, `README.md`, `TODO.md`, and focused docs under `Docs/` when relevant.
- Prefer the smallest real slice that yields useful evidence or safer operation.
- Challenge assumptions when the design starts drifting larger than the problem.
- Prefer trade-off analysis over generic best-practice language.
- Keep code, schemas, SQL, command surfaces, and docs easy to inspect after time away.
- Preserve replaceability at the Protect boundary.
- Keep outputs concise and useful.
- Do not invent future requirements without evidence.
- When uncertain, choose the narrower interpretation and ask before broadening scope.

## Final rule

Build a small, quiet, legible observation pipeline.

Do not build a platform.
