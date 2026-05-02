# Cadence Modeling Layer

## Purpose

`protect-cadence` currently produces a local event warehouse: compact normalized observations plus extraction-oriented query tools.

That is necessary, but not quite sufficient for downstream reasoning about household routine.

This document proposes a separate derived layer that turns raw cadence events into modeled routine structure:

- clustered episodes instead of only raw event rows
- time-conditioned sequence expectations
- descriptive attention scores that tell an LLM what to inspect

The key boundary is:

- `protect-cadence` remains the source of observed evidence
- the modeling layer produces derived hypotheses about routine shape
- the LLM remains the judge of whether a scored irregularity is actually meaningful

## Why this layer exists

Raw event rows are often too fine-grained for good reasoning.

A downstream model should be able to notice things like:
- this kind of episode usually happens at this time on weekdays
- this camera transition usually follows that one within a few minutes
- this hour is usually quiet but activity appeared
- this expected follow-on episode did not appear
- this sequence looks structurally unlike the recent baseline

That is not the same thing as letting the CLI decide what is suspicious.

The goal is attention guidance, not autonomous interpretation.

## Architectural recommendation

Use a separate derived artifact, preferably a parallel SQLite database, rather than mixing modeled state directly into the base cadence database.

Recommended split:

```text
UniFi Protect API
    -> protect-cadence ingest
    -> cadence SQLite
    -> modeling pass
    -> model SQLite
    -> OpenClaw / local agents
```

Reasons to keep it separate:
- modeled state is more experimental and likely to churn
- model outputs should be safely rebuildable from source events
- multiple modeling strategies may eventually coexist
- the base evidence store should stay clean and legible
- recomputation should not threaten raw observation history

This should be treated as a derived cache or materialized interpretation layer, not as the primary source of truth.

## Scope of the first version

The first useful version should do three things:

1. derive episodes from raw events
2. fit a simple time-conditioned sequence model over those episodes
3. score attention-worthy deviations without making final judgments

Do not start with a highly sophisticated probabilistic stack if the episode vocabulary is still unstable.

## Layer 1: episode clustering

The first transformation should collapse noisy nearby rows into more useful activity episodes.

Why:
- LLM reasoning is usually better over "animal activity in Living Room from 06:52 to 07:08" than over many adjacent low-level rows
- sequence modeling over episodes is more meaningful than sequence modeling over every individual normalized row
- downstream anomaly scoring should usually care about routine chunks, not every row boundary emitted by Protect

### Episode goals

An episode should be:
- human-legible
- derivable from source events
- stable enough to reason about across time windows
- simple enough to recompute deterministically

### First-pass episode clustering heuristics

Start with explicit deterministic rules, for example:
- sort normalized events by `time_start`
- open a new episode when the gap from the prior relevant event exceeds a threshold
- allow clustering within a camera or within a small spatial neighborhood if such grouping exists later
- merge adjacent events of related kinds when they look like one activity burst
- preserve source-event linkage for drill-down

Initial clustering may reasonably use:
- camera
- kind
- time gap threshold
- optional settled/unsettled handling

Avoid complex hidden heuristics in v1.

### Possible episode fields

Suggested episode-level fields:
- `episode_id`
- `start_time`
- `end_time`
- `duration_seconds`
- `primary_camera`
- `camera_set`
- `primary_kind`
- `kind_set`
- `event_count`
- `source_event_count`
- `contains_unsettled`
- `time_bucket_hour`
- `time_bucket_weekday`
- `source_window_start`
- `source_window_end`

Suggested linkage tables:
- `episode_events(episode_id, event_row_id)`
- optionally `episode_cameras` and `episode_kinds` if normalization helps queryability

## Layer 2: time-conditioned routine model

After episodes exist, model routine as time-conditioned sequence expectations.

The starting model does not need to be mathematically fancy. It does need to be inspectable.

A practical first version can combine:
- episode frequency by time bucket
- transition counts between episode states
- expected follow-on delay distributions
- absence-of-expected-event checks

### Conditioning dimensions

Start with:
- hour-of-day
- weekday vs weekend
- optionally exact weekday

Later, if useful:
- seasonality
- holiday / travel mode
- before-vs-after a known change point
- recency-weighted windows

Do not front-load those extra dimensions.

### State representation

The state vocabulary matters more than fancy math.

First-pass state representations might be simple composites like:
- primary camera
- primary kind
- coarse duration bucket
- optional multi-camera or multi-kind flags

Examples:
- `living-room:animal:short`
- `driveway:person:medium`
- `entry-doorbell:person:short`
- `den:animal:burst`

If state definitions become too sparse or brittle, back up and simplify them.

### Sequence model shape

A reasonable first pass is a time-conditioned Markov-style model:
- probability of seeing state `S` in time bucket `T`
- probability of transition `S1 -> S2` in bucket `T`
- expected delay between `S1` and `S2`
- expected quiet periods per bucket

This is enough to surface useful irregularities without pretending to deeply understand the home.

## Layer 3: attention scoring

The output of the modeling layer should be attention candidates, not verdicts.

Each candidate should answer:
- what happened or failed to happen
- why the model thinks it is worth attention
- what baseline or comparison supports that claim
- how to drill back into the underlying events and episodes

### Good attention categories

Examples:
- unexpected presence in a usually quiet bucket
- unusual absence of a usually present episode
- unusual transition
- unusual duration or burst size
- unusual camera combination
- unusual kind mixture
- routine-shift signal over a longer comparison window

### Output design goals

The output should be:
- descriptive
- inspectable
- evidence-linked
- rebuildable
- easy for an LLM to summarize

Avoid opaque scalar-only outputs.

Instead of only:
- `anomaly_score = 0.91`

Prefer records shaped more like:
- `attention_type`
- `score`
- `window`
- `observed_state`
- `expected_baseline`
- `reason_features`
- `support_counts`
- `episode_ids`
- `event_drilldown_descriptor`

Implemented `model findings` JSON includes the original flat finding fields plus an
`audit` object for each finding. The audit object is the stable source trail agents
should prefer when explaining why a finding exists:

- `run` identifies the model run, model version, and build time.
- `sourceWindow` records the source evidence range used by the rebuild, when bounded.
- `scoringWindow` records the user-requested findings window, when bounded.
- `observed` describes the current episode and, for transitions, the previous episode.
- `baseline` carries the bucket/state counts, expected duration, expected gap, or transition counts that made the finding attention-worthy.
- `support` lists linked episode IDs and the relevant support counts.
- `drillDown.episodes` gives reproducible `model episodes` filters for the current and, for transitions, previous episode.
- `drillDown.events` gives matching `query events` descriptors for inspecting source event rows.
- `boundaries` states that findings are descriptive attention candidates and exclude live video, thumbnails, and audio.

Human text output intentionally stays compact; the audit contract is for JSON consumers and agents.

## Suggested database split

A separate model database could contain tables like:

### Episode tables
- `episodes`
- `episode_events`
- optional `episode_state_labels`

### Model tables
- `model_runs`
- `state_definitions`
- `state_bucket_stats`
- `state_transition_stats`
- `state_delay_stats`
- `quiet_bucket_stats`

### Attention tables
- `attention_findings`
- `attention_supporting_episodes`
- optional `attention_features`

### Rebuild metadata
- source event range used to train or score
- model version / scoring version
- hyperparameters like gap thresholds and bucket definitions

This makes the model layer reproducible and debuggable.

## CLI and system boundary

The modeling layer should stay subordinate to the evidence layer.

That means:
- it may read from the cadence database
- it may emit episode rows and attention findings
- it should not replace raw event querying
- it should not hide source evidence
- it should not produce final user-facing behavioral judgments on its own

The LLM should still be able to ask:
- show me the underlying events
- compare this to similar prior windows
- explain why this scored highly
- is this a sustained change or a one-off oddity?

## First implementation path

Recommended order:

1. Add an explicit design note and vocabulary for episodes, states, and attention findings.
2. Implement deterministic episode clustering over the existing cadence event table.
3. Materialize episode tables in a separate SQLite database.
4. Add simple time-bucket frequency and transition statistics.
5. Add first-pass attention scoring with transparent reasons.
6. Add query or export surfaces that let OpenClaw pull the top findings plus drill-down links.
7. Re-evaluate whether more sophisticated sequence modeling is actually needed.

## Current implementation status

The first end-to-end slice now exists inside the main `protect-cadence` executable.

Current command surface:
- `protect-cadence model rebuild`
- `protect-cadence model episodes`
- `protect-cadence model findings`

Current derived database behavior:
- source evidence remains in `protect-cadence.sqlite`
- modeled state is written to a separate sibling SQLite database by default
- rebuilds are full rebuilds
- `protect-cadence model rebuild` now emits rebuild duration in its JSON response so operator pain is visible
- there is no daemon, no incremental refresh path, and no background service

Current implemented tables:
- `model_runs`
- `episodes`
- `episode_events`
- `episode_kinds`
- `state_bucket_stats`
- `state_transition_stats`
- `attention_findings`
- `attention_finding_episodes`

Current implemented episode rule:
- group normalized events only within a single camera
- start a new episode when the next event starts more than 5 minutes after the current episode end
- allow mixed kinds inside an episode
- choose `primary_kind` by highest normalized-row count, then first appearance, then lexical tie-break
- derive `state_key` as `camera:primary_kind`

Current implemented bucket statistics:
- local `hour_of_day`
- `weekday` vs `weekend`
- episode counts plus simple duration summaries per state bucket
- same-camera consecutive transition counts plus simple gap summaries per `from_state -> to_state` bucket

Current implemented findings:
- `unexpected_presence`
- `unexpected_transition`
- `unusual_duration`

Current `unexpected_transition` behavior is intentionally simple:
- transitions only consider consecutive episodes within the same camera
- findings require an exact `from_state -> to_state` pair to have repeated support overall
- the emitted finding is the first rare local hour/day-class bucket for that otherwise repeated pair

Current `unusual_duration` behavior is intentionally narrow:
- it only flags longer-than-usual episodes for now
- it requires bucket support before emitting a finding
- shorter-than-usual episodes are intentionally deferred until the current shape proves useful

## Deferred design cautions

### Incremental refresh

Incremental refresh is intentionally deferred until full rebuilds become meaningfully too slow in practice.

Current reasoning:
- full rebuilds are easier to trust while episode rules and finding semantics are still changing
- late-arriving source events can change episode boundaries, transition counts, and downstream findings near the rebuild edge
- a mutable incremental cache would add invalidation and repair logic before the model semantics have stabilized

Current practical threshold:
- prefer full rebuilds until measured rebuild duration becomes an actual operator problem
- use the emitted rebuild-duration field from `protect-cadence model rebuild` to judge that with real data rather than guessing early

If incremental refresh is explored later, a conservative rolling-tail recompute is the preferred first step rather than fine-grained in-place patching.

### Cross-camera stitching

Cross-camera stitching is also intentionally deferred.

Current reasoning:
- single-camera episodes are easier to inspect and less likely to smuggle in false assumptions about identity or movement
- true multi-camera stitching would need some explicit story about camera adjacency, likely travel paths, or house topology
- without that, the system risks inventing a single activity from unrelated nearby detections

Current preferred path:
- keep base episodes camera-local
- learn from cross-camera transition patterns first if they become useful
- only add a higher-level stitched layer later as an explicit derived abstraction that preserves the original episode evidence underneath

## Things to avoid early

Avoid these in the first modeling pass:
- deep learning or embedding-heavy sequence models
- hidden feature engineering that is hard to inspect later
- direct anomaly verdicts without explanation
- mixing modeled state into the base event table
- pretending sparse cameras imply stronger semantics than they really do
- overfitting to one short observation window

## Success criteria

This layer is successful if it helps downstream reasoning answer questions like:
- what should I pay attention to this morning?
- what looked structurally different from the recent routine?
- what expected follow-on pattern failed to happen?
- is this a one-off oddity or the beginning of a change?

while preserving a clean path back to source evidence.

## Open questions

Important unresolved design choices:
- whether this belongs in the same repository or a sibling package once it grows
- what the first stable episode vocabulary should be
- whether spatial grouping across cameras should exist before explicit house topology exists
- how aggressively to model absences, since absence-detection can become noisy quickly
- how much recency weighting should matter relative to longer baseline windows

## Working name

This document uses **Cadence Modeling Layer** for the implementation boundary.

"Routine modeling" is also a good user-facing description, but "cadence modeling" makes the dependency on the underlying cadence event store clearer.
