---
name: protect-cadence
description: Local read/query access to UniFi Protect detection evidence plus derived cadence-model findings. Use when answering questions about what camera detections happened, how activity compares across time windows, or what routines or deviations can be inferred from the local evidence store.
---

# protect-cadence

Local, read-only pipeline for turning camera detections into a queryable evidence store and derived cadence patterns.

Cameras are treated as sensors. The goal is to retrieve observations and compare patterns over time.

Interpret patterns at the household level, not individual events. Interpret in combination with other sources of information that you have access to.

---

## Model

Entities:
- event (normalized detection: time, camera, kind)
- evidence (local history of events)
- derived patterns (episodes, transitions, aggregated activity)
- annotation (durable human commentary attached to a target)
- query window (explicit bounded time slice)

Data types:
- canonical: direct detection evidence
- derived: computed patterns over that evidence
- interpretive: sidecar human context that explains how to treat evidence later

---

## Core behavior

- retrieve evidence first, then interpret
- prefer canonical data for facts
- use derived patterns for context
- keep facts separate from inference
- prefer structured output when available

---

## Core commands (illustrative)

- `protect-cadence query events --last-hours 6 --format json`
- `protect-cadence query events --last-hours 24 --camera Driveway --format json`
- `protect-cadence query summary --last-hours 24 --format json`
- `protect-cadence query compare --last-hours 2 --vs-prior-window --format json`
- `protect-cadence model findings --last-hours 24 --format json`
- `protect-cadence annotations kinds --format json`
- `protect-cadence annotations targets --account default --format json`
- `protect-cadence annotations list --account default --target-kind camera --target-id name:Driveway --format json`
- `protect-cadence validate --format json`

Not exhaustive. Use `--help` and adapt to the current interface.

---

## Observation policy

When asked what happened:

1. query a relevant time window from local evidence
2. present events or summaries
3. optionally compare against another window
4. use derived patterns only as supporting context

Do not skip the evidence layer unless explicitly requested.

---

## Time and comparison

Time windows are the primary unit of meaning.

Useful operations:
- slicing events within a window
- grouping by time (hour, weekday, etc.)
- comparing one window to another
- observing changes in activity levels or patterns

Interpret results in terms of differences across windows, not isolated events.

---

## Reasoning policy

Infer routines or deviations from:
- frequency by camera, kind, and time
- comparisons across windows
- recurring patterns or absence of activity
- derived episodes or transition patterns

Rules:
- describe evidence briefly
- distinguish observed vs inferred
- surface weak or ambiguous signals
- avoid treating the tool as an anomaly judge

---

## Read-only exploration mode

Normal answers should use stable CLI verbs first. Before writing SQL, run `protect-cadence --help` and relevant subcommand help when semantics are unclear.

Use read-only SQLite/Datasette exploration only for source coverage, table shape, freshness, event → episode → finding traceability, debugging surprising output, or discovering a repeated pattern that may deserve a future CLI/model verb. For canned SQL, Datasette setup, and camera-data privacy boundaries, read `references/read-only-exploration.md` from this skill folder.

Read-only SQL rules:
- open evidence/model DBs read-only / immutable
- keep queries narrow and explain the exploration question
- report counts, freshness, model run metadata, and caveats
- do not treat ad hoc SQL as the normal chat contract
- never mutate tables, annotations, schema, model rows, or source evidence
- do not infer identity, mood, safety, relationships, or private behavior from detections
- do not join camera evidence with other personal data unless the user request clearly requires it

---

## Durable interpretive context / annotations

If a human gives feedback, corrections, or commentary that would materially change how future tool users should interpret Protect evidence, pause and ask whether they want that context remembered durably as an annotation.

This applies especially to commentary about:

- a camera: noisy source, privacy caveat, renamed camera, construction/test period, or "summarize this camera only at a high level"
- an event: false positive, expected delivery/visitor, camera test, maintenance activity, or not representative of routine
- an episode or finding: known context, "do not treat this as routine-changing," or model output that needs a human caveat
- a context/window: family/privacy rule, recurring situation, construction week, school-morning window, or interpretation rule for a class of future questions

Ask plainly, using memory/durability/annotation language rather than generic "save this?" phrasing. Good examples:

```text
That changes how I'd interpret this evidence later. Should I remember it as a Protect annotation?
```

```text
Should I add that as durable commentary on this camera/event/window?
```

```text
Want me to attach that as an annotation so future Protect lookups see the caveat?
```

If the human approves, attach an annotation rather than changing source evidence, model rows, privacy policy, or routine/recommendation machinery. Keep the body plain-English and interpretive:

```bash
protect-cadence annotations add \
  --account default \
  --target-kind camera \
  --target-id name:Driveway \
  --body "Driveway detections during construction week are noisy; do not treat them as a new routine." \
  --source human
```

Use `annotations kinds` to discover allowed target kinds, and `annotations targets` to reuse local target-id conventions before inventing a new one. Current target kinds are `camera`, `event`, `episode`, `finding`, `zone`, `context`, and `window`.

Prefer stable target IDs:

- `camera`: `id:<camera-id>` when available, or `name:<camera name>`
- `event`: `event_id:<protect-event-id>#kind:<kind>`
- `episode`: `run:<run-id>/episode:<episode-id>`
- `finding`: `run:<run-id>/finding:<finding-id>`
- `context`: handles such as `family-privacy`, `school-morning`, or `construction-week`
- `window`: documented handles such as `window:school-morning`, or explicit local conventions

Annotations are attached context, not source evidence, derived cadence facts, privacy enforcement, ratings, alarms, or judgments. Inline annotations are included by default where query/model outputs naturally encounter their targets; use `--no-annotations` on supported query/model commands to omit them.

---

## Response

- concise
- evidence-backed
- indicate inferred vs observed
- acknowledge weak or missing data

---

## Style

retrieve → compare → interpret → respond  
patterns over raw events  
tool provides evidence, not conclusions
