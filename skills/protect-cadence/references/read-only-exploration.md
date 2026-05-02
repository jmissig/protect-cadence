# Read-Only Exploration Surface

> Skill copy: this exploration guide is also bundled at `skills/protect-cadence/references/read-only-exploration.md` so agents can use it without access to the source repo. Keep the two copies in sync when editing exploration guidance.

`protect-cadence` has two normal ways to look at camera-activity evidence:

1. **Stable CLI verbs** for normal Robut/chat answers and scripts.
2. **Read-only SQLite/Datasette exploration** for inspection, debugging, faceting, and discovering what future CLI/model verbs should expose.

Use the CLI first when the question fits an existing command. Use read-only SQL when the question is about source coverage, table shape, surprising output, missing evidence, event → episode → finding traceability, or a one-off investigation that should not become the normal chat contract yet.

## Boundaries

Read-only exploration is for looking, not deciding.

Do:

- open evidence/model/annotation databases read-only;
- inspect counts, freshness, examples, support rows, and attached human commentary;
- use SQL to debug whether CLI/model output is missing evidence or over-weighting stale evidence;
- keep camera data at the household-activity sensor layer;
- turn repeated useful SQL patterns into future CLI verbs or docs.

Do not:

- write to the evidence database during inspection;
- write to the model database except through `protect-cadence model rebuild`;
- write annotations directly with SQL; use `protect-cadence annotations add` only after human approval;
- use SQL as the default Robut answer path when a stable CLI command exists;
- expose or request video, thumbnails, clips, audio, faces, or identity-level media surfaces;
- infer mood, relationships, safety, identity, work habits, or private behavior from detections;
- silently join camera evidence with calendar, messages, location, food, or other personal data unless the user request clearly requires it.

When unsure, run `protect-cadence --help` and the relevant subcommand help before writing SQL. The CLI help documents current semantics better than a stale query snippet will.

## Database paths

The evidence database stores normalized detection rows. The model database stores rebuildable derived episodes, bucket/transition stats, and attention findings. The annotations database stores writable human commentary as a sibling sidecar; it is interpretive context, not source evidence or model output.

Default managed paths are:

```text
~/Library/Application Support/protect-cadence/protect-cadence.sqlite
~/Library/Application Support/protect-cadence/protect-cadence-model.sqlite
~/Library/Application Support/protect-cadence/protect-cadence-annotations.sqlite
```

Local repo/test runs may instead use an explicit `--db` or a working-directory `protect-cadence.sqlite`. To resolve configured paths, prefer CLI output:

```bash
protect-cadence query summary --last-hours 1 --format json
protect-cadence model findings --last-hours 1 --format json
```

For model rebuilds, both databases can be pointed explicitly:

```bash
protect-cadence model rebuild \
  --db /path/to/protect-cadence.sqlite \
  --model-db /path/to/protect-cadence-model.sqlite
```

## Launch Datasette read-only

Open the evidence DB read-only with Datasette:

```bash
datasette "$HOME/Library/Application Support/protect-cadence/protect-cadence.sqlite" --immutable
```

Open evidence, model, and annotations DBs:

```bash
datasette \
  "$HOME/Library/Application Support/protect-cadence/protect-cadence.sqlite" \
  "$HOME/Library/Application Support/protect-cadence/protect-cadence-model.sqlite" \
  "$HOME/Library/Application Support/protect-cadence/protect-cadence-annotations.sqlite" \
  --immutable
```

For safer scratch exploration:

```bash
mkdir -p .tmp
cp "$HOME/Library/Application Support/protect-cadence/protect-cadence.sqlite" .tmp/protect-cadence-exploration.sqlite
cp "$HOME/Library/Application Support/protect-cadence/protect-cadence-model.sqlite" .tmp/protect-cadence-model-exploration.sqlite
if [ -f "$HOME/Library/Application Support/protect-cadence/protect-cadence-annotations.sqlite" ]; then
  cp "$HOME/Library/Application Support/protect-cadence/protect-cadence-annotations.sqlite" .tmp/protect-cadence-annotations-exploration.sqlite
  datasette .tmp/protect-cadence-exploration.sqlite .tmp/protect-cadence-model-exploration.sqlite .tmp/protect-cadence-annotations-exploration.sqlite --immutable
else
  datasette .tmp/protect-cadence-exploration.sqlite .tmp/protect-cadence-model-exploration.sqlite --immutable
fi
```

## Core tables

Evidence DB:

- `events` — normalized detection rows. One source Protect event may produce multiple rows when it has multiple smart-detect kinds.
  - important columns: `time_start`, `time_end`, `camera_id`, `camera`, `event_type`, `kind`, `event_id`
  - `event_id + kind` is the dedupe key

Model DB:

- `model_runs` — model build metadata, source evidence path/count/window, model version, thresholds
- `episodes` — deterministic activity episodes derived from event rows
- `episode_events` — episode → source event row support
- `episode_kinds` — kind counts inside each episode
- `state_bucket_stats` — observed episode counts/durations by camera/kind/hour/day class
- `state_transition_stats` — observed transitions between camera/kind states
- `attention_findings` — descriptive attention candidates produced from the model
- `attention_finding_episodes` — finding → supporting/context episodes

Annotations DB:

- `annotations` — human-readable interpretive notes attached to targets such as cameras, events, episodes, findings, contexts, and windows
  - important columns: `account`, `target_kind`, `target_id`, `body`, `source`, `created_at`, `updated_at`
  - annotations are attached context, not source events, derived cadence facts, privacy enforcement, or judgments

## Canned exploration queries

### Evidence freshness

```sql
SELECT
  COUNT(*) AS event_rows,
  COUNT(DISTINCT event_id) AS source_events,
  MIN(time_start) AS first_event,
  MAX(time_start) AS latest_event
FROM events;
```

Caveat: `event_rows` counts normalized kind rows. Use `COUNT(DISTINCT event_id)` when asking about source Protect events.

### Annotation targets that may affect interpretation

Prefer the CLI for writing and normal discovery:

```bash
protect-cadence annotations kinds --format json
protect-cadence annotations targets --account default --format json
protect-cadence annotations list --account default --target-kind camera --target-id name:Driveway --format json
```

Use SQL only for read-only inspection across many annotation targets:

```sql
SELECT
  account,
  target_kind,
  target_id,
  COUNT(*) AS annotations,
  MAX(updated_at) AS last_updated_at
FROM annotations
GROUP BY account, target_kind, target_id
ORDER BY last_updated_at DESC, target_kind, target_id
LIMIT 50;
```

Caveat: annotations may change how future answers should phrase or caveat evidence, but they are not source rows, model facts, ratings, alarms, or privacy enforcement.

### Recent activity by camera and kind

```sql
SELECT
  camera,
  kind,
  COUNT(*) AS event_rows,
  COUNT(DISTINCT event_id) AS source_events,
  MIN(time_start) AS first_seen,
  MAX(time_start) AS last_seen
FROM events
WHERE time_start >= datetime('now', '-24 hours')
GROUP BY camera, kind
ORDER BY event_rows DESC, camera, kind;
```

Caveat: SQLite `datetime('now')` is UTC. CLI local-time filters are often clearer for chat answers.

### Hour-of-day distribution

```sql
SELECT
  strftime('%H', time_start, 'localtime') AS local_hour,
  camera,
  COUNT(*) AS event_rows,
  COUNT(DISTINCT event_id) AS source_events
FROM events
WHERE time_start >= datetime('now', '-7 days')
GROUP BY local_hour, camera
ORDER BY local_hour, camera;
```

Prefer the CLI for normal use:

```bash
protect-cadence query summary --last-hours 168 --group-by hour --group-by camera --format json
```

### Same-weekday prior windows

Prefer the CLI helper for this shape:

```bash
protect-cadence query compare \
  --since "2026-04-27 08:00" \
  --until "2026-04-27 10:00" \
  --vs-same-weekday-prior-weeks 4 \
  --group-by camera \
  --group-by kind \
  --format json
```

Use SQL only when debugging the helper or investigating a shape the CLI cannot express.

### Latest model run

```sql
SELECT
  id,
  built_at,
  model_version,
  source_database_path,
  source_event_count,
  source_window_start,
  source_window_end,
  quiet_gap_seconds
FROM model_runs
ORDER BY built_at DESC
LIMIT 5;
```

Caveat: model rows are rebuildable derived evidence. Do not treat old findings as timeless facts; always keep the run metadata attached.

### Episodes by camera/kind

```sql
SELECT
  camera,
  primary_kind,
  COUNT(*) AS episodes,
  SUM(event_count) AS event_rows,
  SUM(source_event_count) AS source_events,
  ROUND(AVG(duration_seconds), 1) AS avg_duration_seconds,
  MIN(start_time) AS first_episode,
  MAX(start_time) AS latest_episode
FROM episodes
WHERE run_id = (SELECT MAX(id) FROM model_runs)
GROUP BY camera, primary_kind
ORDER BY episodes DESC, camera, primary_kind;
```

### Attention findings with support counts

```sql
SELECT
  id,
  finding_type,
  camera,
  primary_kind,
  episode_start_time,
  episode_end_time,
  hour_of_day,
  day_class,
  score,
  bucket_episode_count,
  state_episode_count,
  observed_duration_seconds,
  expected_duration_seconds,
  previous_primary_kind,
  transition_bucket_count,
  transition_pair_count
FROM attention_findings
WHERE run_id = (SELECT MAX(id) FROM model_runs)
ORDER BY score DESC, episode_start_time DESC
LIMIT 25;
```

Caveat: a finding is an attention candidate relative to the current model, not a judgment that something is important, bad, suspicious, or personally meaningful.

### Finding → episode → event trace

```sql
SELECT
  af.id AS finding_id,
  af.finding_type,
  afe.relation,
  e.id AS episode_id,
  e.camera,
  e.primary_kind,
  e.start_time,
  e.end_time,
  e.event_count,
  ee.event_row_id,
  ee.source_event_id,
  ev.time_start AS event_time_start,
  ev.kind AS event_kind
FROM attention_findings af
JOIN attention_finding_episodes afe ON afe.finding_id = af.id
JOIN episodes e ON e.id = afe.episode_id
LEFT JOIN episode_events ee ON ee.episode_id = e.id
LEFT JOIN events ev ON ev.id = ee.event_row_id
WHERE af.run_id = (SELECT MAX(id) FROM model_runs)
  AND af.id = ?
ORDER BY afe.relation, e.start_time, ee.ordinal;
```

Replace `?` with a specific `attention_findings.id`. If using Datasette, parameterized query support is preferable to string-splicing.

### Bucket stats behind a state

```sql
SELECT
  camera,
  primary_kind,
  hour_of_day,
  day_class,
  episode_count,
  state_episode_count,
  average_duration_seconds,
  min_duration_seconds,
  max_duration_seconds
FROM state_bucket_stats
WHERE run_id = (SELECT MAX(id) FROM model_runs)
  AND camera = ?
  AND primary_kind = ?
ORDER BY day_class, hour_of_day;
```

Use this to inspect what the model has observed for a state. Do not convert it directly into a human-facing routine claim without context.

### Transition stats behind a finding

```sql
SELECT
  camera,
  from_primary_kind,
  to_primary_kind,
  hour_of_day,
  day_class,
  transition_count,
  pair_transition_count,
  average_gap_seconds,
  min_gap_seconds,
  max_gap_seconds
FROM state_transition_stats
WHERE run_id = (SELECT MAX(id) FROM model_runs)
ORDER BY transition_count DESC, camera, hour_of_day
LIMIT 50;
```

## When to promote SQL into the CLI

A SQL pattern may deserve a stable command or option when:

- it answers a repeated Robut question;
- it needs consistent local-time semantics;
- it needs drill-down descriptors;
- it needs privacy/join guardrails;
- it is easy to misread from raw rows.

Until then, keep SQL exploration narrow, cite the tables/filters used, and explain caveats.
