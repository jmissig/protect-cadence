---
name: protect-cadence
description: Local read/query access to UniFi Protect detection evidence plus derived cadence-model findings. Use when answering questions about what camera detections happened, how activity compares across time windows, what routines or deviations can be inferred from the local evidence store, or how to build, test, document, or operate the protect-cadence CLI and codebase.
---

# protect-cadence

Local-first ingest, storage, and query tooling for UniFi Protect detection evidence. UniFi Protect is a camera system; `protect-cadence` treats cameras as sensors and turns bounded detection data into a local SQLite evidence store plus a rebuildable derived model layer.

## Model

Entities:
- event row (normalized detection observation with time, camera, kind, and event identity)
- evidence database (canonical local SQLite history of observed detections)
- model database (derived, rebuildable routine/cadence layer)
- query window (explicit bounded time slice used for events, summaries, and comparisons)

Data types:
- canonical: direct normalized Protect detection evidence imported into SQLite
- derived: rebuildable modeled structure such as episodes, transition patterns, and attention-worthy findings

## Core behavior

- retrieve evidence first, then interpret
- prefer canonical event data for facts
- use model outputs for descriptive attention guidance, not verdicts
- keep facts separate from inference
- structured output is often available for LLM processing

## Core commands (illustrative)

- `protect-cadence ingest --last-hours 6`
- `protect-cadence query events --last-hours 24 --format json`
- `protect-cadence query summary --last-hours 24 --format json`
- `protect-cadence query compare --last-hours 1 --vs-prior-window --format json`
- `protect-cadence model rebuild`
- `protect-cadence model findings --last-hours 24 --format json`
- `protect-cadence model episodes --camera Driveway --format json`
- `protect-cadence validate --format json`

Not exhaustive. Use `--help` and adapt to the current interface.

## Observation policy

When asked what happened:
1. query the local evidence DB first
2. present the relevant slice, summary, or comparison
3. use the model layer only as secondary descriptive context

Do not skip the evidence layer unless explicitly asked.

## Reasoning policy

Infer routine or deviation from:
- event frequency by camera, kind, and time window
- comparisons across explicit windows
- derived episodes
- model findings and transition patterns

Rules:
- describe evidence briefly
- separate observed vs inferred
- surface weak evidence or ambiguity
- avoid treating the CLI as an anomaly judge

## Response

- concise
- evidence-backed
- indicate inferred vs observed
- acknowledge weak or missing data

## Style

retrieve → compare/model → respond  
small query surface over raw API mirroring  
tool provides evidence, not conclusions
