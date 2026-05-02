# Pattern Boundary and Corrections — protect-cadence

This note turns the broader OpenClaw pattern-intelligence work into concrete guidance for `protect-cadence`.

Related Obsidian notes:
- `LLM Pattern Loop`
- `Pattern Extraction Tooling`
- `Personal Pattern Intelligence`
- `Environmental Pattern Intelligence`
- `Almanacs and Guides`

Related repo notes:
- `Docs/pattern-intelligence-proposal.md`
- `Docs/cadence-modeling-layer.md`
- `Docs/read-only-exploration.md`

## Boundary

`protect-cadence` is a household activity evidence/model instrument, not a meaning engine.

The useful layering is:

```text
Protect detections
  -> normalized evidence rows
  -> episodes / buckets / transition stats / descriptive findings
  -> Robut-composed household context or attention note
  -> human correction or privacy policy where needed
```

The key distinction remains:

> attention-worthy does not mean meaningful, suspicious, or important.

Datasette/read-only SQL is the microscope for model inspection. CLI commands are bounded instruments for events, summaries, comparisons, episodes, and model findings. Robut composes any House Activity Almanac/Guide or explanation.

## What belongs in `protect-cadence`

Good tool-layer work:

- source/controller freshness and ingest coverage;
- event queries by camera, kind, date, hour, weekday, and explicit windows;
- summaries with support counts and preserved zero/empty buckets;
- comparisons and baselines;
- deterministic episodes/sessionization where raw detections are too noisy;
- descriptive model findings such as unusual duration or rare transition, with support counts and drill-downs;
- model-stat inspection when Datasette/canned SQL is insufficient;
- privacy-aware source trails that identify cameras/kinds/windows without over-sharing in human-facing prose.

## What stays above `protect-cadence`

Do not make the CLI decide:

- why a person or animal was present;
- whether an event is suspicious, welcome, annoying, or meaningful;
- household routine explanations;
- cross-source joins with calendars, messages, weather, or family context;
- human-facing Guide prose;
- durable meaning changes.

Those are Robut/Guide-layer interpretations and often require human context.

## Human-attached notes, not correction machinery

Near-term correction handling should be simple: a human attaches a plain-English note to the thing Robut is likely to encounter again. The note supplies context; the LLM decides how to use it next time.

The hard part is not schema. The hard part is **what object the note attaches to** and **where Robut will reliably find it later**.

Useful attachment targets for `protect-cadence`:

- a camera, for privacy or noisy-source caveats;
- an event/detection, for false positive or expected-activity notes;
- an episode/window, for maintenance, parties, construction, or camera tests;
- a model finding, for “do not treat this as routine-changing” notes;
- an audience/context, for what can be surfaced in shared answers.

Example notes:

- Camera note: “Driveway alerts during construction week are noisy; do not treat them as a new routine.”
- Event note: “This person detection was a known delivery, not unusual household activity.”
- Privacy note: “In family/shared answers, summarize this camera at a high level only.”

Store durable machine-retrievable notes in the annotations sidecar database, not in the source evidence database. Raw detections stay immutable and can remain read-only to Robut. The CLI may use explicit ignore/noise notes as filters later, but it should not infer the note’s meaning itself.

The durable shape intentionally mirrors `swarm-cadence`:

```text
id
account
target_kind
target_id
body
source
created_at
updated_at
```

Supported target kinds are `camera`, `event`, `episode`, `finding`, `zone`, `context`, and `window`.

Target ID conventions:

- `camera`: prefer `id:<camera-id>` when available; use `name:<camera name>` when the camera ID is unavailable or a human naturally names the camera.
- `event`: use `event_id:<protect-event-id>#kind:<kind>` because one Protect event can produce multiple normalized kind rows.
- `episode`: use `run:<run-id>/episode:<episode-id>`; this is rebuild-scoped, not timeless evidence.
- `finding`: use `run:<run-id>/finding:<finding-id>`; this is rebuild-scoped and should be used for commentary on a specific model output.
- `window`: use a documented handle such as `window:school-morning`, or an explicit convention including camera/kind/since/until when the note is about a bounded slice.
- `context`: use durable handles such as `family-privacy`, `school-morning`, or `construction-week`.
- `zone`: reserve for stable Protect zone identifiers once those are modeled.

That is enough for Robut to find the note and reason from it without rewriting source evidence.

## Actionable next slices

1. **Model finding drill-down contract**
   - Keep the implemented per-finding JSON `audit` object stable enough for Robut: source/scoring windows, support counts, baseline, comparison value, exact event/episode query descriptors, and descriptive boundaries.

2. **Attached-note examples**
   - Add small examples for false positive, ignore window, routine exception, and privacy policy.
   - Decide which ones should affect model rebuilds versus only Robut presentation.

3. **Model-stat inspection command only if needed**
   - If repeated Datasette/canned SQL inspection is needed for `state_bucket_stats` or `state_transition_stats`, add a read-only inspection command.

4. **Privacy/audience guardrails**
   - Document which fields are safe for direct user answers, family/shared answers, and debugging-only output.
