# Pattern Intelligence Proposal — protect-cadence

## Thesis

`protect-cadence` should remain the household camera-activity evidence layer: compact normalized detections, rebuildable model outputs, descriptive attention findings, and drill-downs that help Robut inspect routine shape without granting agents live video access or turning the CLI into a behavioral-judgment engine.

The next pattern-intelligence step is not “just expose SQLite to the LLM.” It is to clarify two sibling surfaces:

1. **Explore/inspect surface** — read-only SQLite/Datasette-style access for humans and trusted agents to inspect evidence/model databases, debug ingest/model pipelines, facet events/episodes/findings, and discover better questions.
2. **Stable verb / evidence-substrate surface** — stable `protect-cadence query` and `model` commands that return bounded JSON/source outputs with explicit semantics, provenance, drill-down descriptors, privacy/join policy, and no improvised arbitrary SQL during normal conversation. Robut composes any higher-level evidence packet or household-facing artifact above this layer.

This treats Dogsheep/Datasette as a practical local personal-data-warehouse precedent while preserving the repo’s central boundary: cameras are sensors, not media surfaces, and downstream tools interpret evidence.

## Source research notes

This proposal adapts the Obsidian research notes:

- `Pattern Extraction Tooling` — `/Users/robut/Library/Mobile Documents/iCloud~md~obsidian/Documents/ChingMi/OpenClaw/Pattern Extraction Tooling.md`
- `LLM Pattern Loop` — `/Users/robut/Library/Mobile Documents/iCloud~md~obsidian/Documents/ChingMi/OpenClaw/LLM Pattern Loop.md`
- `Personal Pattern Intelligence` — `/Users/robut/Library/Mobile Documents/iCloud~md~obsidian/Documents/ChingMi/OpenClaw/Personal Pattern Intelligence.md`
- `Pattern Intelligence Research Index` — `/Users/robut/Library/Mobile Documents/iCloud~md~obsidian/Documents/ChingMi/OpenClaw/Pattern Intelligence Research Index.md`
- `Almanacs and Guides` — `/Users/robut/Library/Mobile Documents/iCloud~md~obsidian/Documents/ChingMi/OpenClaw/Almanacs and Guides.md`

## Vocabulary boundary

Keep the tool-side language precise, but do not leak it into the human-facing experience. In repo implementation docs, terms like SQLite, sidecar, source bundle, provenance, derived observation, and drill-down are still useful. Use evidence packet for the Robut-composed decision artifact, not as the default name for every CLI response. In Robut-facing or human-facing artifacts, prefer the warmer vocabulary from `Almanacs and Guides`:

- **Almanac** for durable sourced understanding over time;
- **Guide** for situated help with a task or question;
- **Lens** for a mode/filter/assumption;
- **Option** for a candidate item/action;
- **Source trail** for provenance/drill-down;
- **Edit** for human correction or policy override.

Implementation rule of thumb: compute facts freely when they are traceable and rebuildable; change meaning only with human authority.

## Current strengths

`protect-cadence` is already the strongest local precedent for derived pattern evidence:

- canonical local SQLite evidence database built from normalized Protect event rows;
- optional separate model database, rebuildable from the evidence DB;
- explicit CLI surfaces for events, summaries, comparisons, episodes, and findings;
- deterministic episodes that compress noisy event rows into more useful reasoning units;
- bucket/transition statistics and descriptive attention findings;
- support counts, baselines, reason features, and drill-down descriptors;
- repo-level guardrails against dashboards, clip browsing, live video access, and anomaly verdicts.

Its best reusable design lesson is: **attention-worthy is not necessarily meaningful**. The tool should surface evidence for inspection; Robut decides how, whether, and when to mention it.

## Gaps relative to the 17-verb pattern map

`protect-cadence` covers many verbs but needs clearer boundaries around exploration, correction, and privacy:

- **Prepare / scope:** the CLI can query windows, cameras, kinds, and model findings, but does not yet make “why are we looking?” or source-join policy explicit in packets.
- **Collect / normalize:** strong today. Continue resisting full Protect mirroring.
- **Integrate / join cautiously:** this is the highest-risk gap. Camera activity should almost never be joined with food/location/calendar patterns unless the user asks or a practical household question clearly requires it.
- **Summarize / compare / baseline:** strong. Preserve support counts and denominators, including empty/zero buckets where absence matters.
- **Segment / cadence / lapse:** strong through episodes and model buckets; further segmentation should remain local, explicit, and reversible.
- **Classify / label provisionally:** attention finding types are useful labels, but they need scoped language: `unexpected_presence` means “unexpected relative to this model/window,” not “important,” “bad,” or “suspicious.”
- **Explain / cite / drill down:** already good; make evidence-output fields more uniform across findings, episodes, and summaries.
- **Simulate / adjust assumptions:** possible via alternate windows/baselines/model rebuild parameters, but should not be rushed into interactive controls until the semantics are clear.
- **Critique / correct:** currently underdeveloped. Humans may need to mark false-positive camera/kind names, special household periods, known events, or “do not surface this kind of finding.” Corrections should not rewrite raw evidence.
- **Decay / retire:** model findings must carry model version, generated-at, source window, and scoring window so old attention claims do not become timeless facts.
- **Export / preserve:** SQLite DBs are a good start; schema docs, canned Datasette metadata, and source/derived-output examples would improve portability.

## Two-surface design

### 1. SQLite / Datasette explore-inspect surface

Purpose: inspect the evidence and model databases directly when debugging or doing careful research.

Recommended scope:

- document read-only exploration of both DBs, preferably against copied or immutable paths;
- provide a small set of canned SQL examples rather than encouraging blind table spelunking;
- expose useful facets:
  - events by camera/kind/hour/day;
  - ignored/normalized event-shape coverage when available;
  - episode counts, durations, source event counts;
  - bucket stats and transition stats;
  - attention findings by type, window, support count, model run;
  - drill-down from a finding to supporting episodes and source event rows.

This surface is especially valuable for model debugging because the current derived layer has multiple stages:

```text
Protect API events
  -> normalized event evidence DB
  -> deterministic episodes
  -> bucket / transition stats
  -> attention findings
```

A Datasette-style view should make those transformations inspectable. It should not become the default way Robut answers “what happened?” in chat.

### 2. Stable verb / evidence-substrate surface

Purpose: provide safe, bounded grounding for Robut. The CLI supplies evidence pieces; Robut owns scenario composition, interpretation, and whether to say anything at all.

Current commands already point in the right direction:

```bash
protect-cadence query events --last-hours 24 --format json
protect-cadence query summary --last-hours 24 --format json
protect-cadence query compare --last-hours 1 --vs-same-window-last-week --format json
protect-cadence model findings --last-hours 24 --format json
protect-cadence model episodes --camera Driveway --since 2026-04-14T00:00:00Z --format json
```

A Robut-composed household-activity packet could be a thin, explicit composition over those verbs:

```json
{
  "kind": "protect_cadence.activity_context.v0",
  "query": {
    "window": "last_24h",
    "scope": "household_activity_context",
    "included_sources": ["protect_cadence_evidence_db", "protect_cadence_model_db"],
    "excluded_sources": ["video", "thumbnails", "audio"]
  },
  "freshness": {
    "latest_event_start": "2026-04-26T11:52:00-07:00",
    "model_generated_at": "2026-04-26T12:00:00-07:00"
  },
  "summary": {
    "event_rows": 42,
    "episodes": 11,
    "cameras_with_activity": ["Driveway", "Entry"],
    "kinds": ["person", "animal", "vehicle"]
  },
  "attention_findings": [
    {
      "type": "unexpected_presence",
      "language": "activity in a usually quiet bucket",
      "support_counts": {"observed_episodes": 2, "baseline_bucket_observations": 31},
      "confidence": "descriptive_model_only",
      "drilldowns": [
        "protect-cadence model episodes --since ... --until ... --format json",
        "protect-cadence query events --since ... --until ... --camera Entry --format json"
      ]
    }
  ],
  "boundaries": [
    "No live video or thumbnails included",
    "Findings are attention candidates, not household judgments",
    "Do not join with other household data unless the user request requires it"
  ]
}
```

This composition gives Robut enough to say “there was unusual entry activity compared with recent baselines” while avoiding creepy leaps such as “someone is behaving oddly.”

## Recommended next slices

Small, practical slices that fit the repo’s current direction:

1. **Document Datasette/read-only exploration workflow** — add commands/cautions for opening evidence and model DBs read-only, plus canned SQL for event → episode → finding traceability.
2. **Stabilize shared evidence-output fields in docs** — define required fields for model findings JSON: query window, model run, finding type, baseline, support counts, reason features, drill-down commands, privacy notes. Do not require the CLI to emit the final Robut packet.
3. **Add direct inspection only where needed** — the existing TODO about `state_bucket_stats` and `state_transition_stats` is the right place to decide whether inspection commands are needed; Datasette may cover operator debugging before adding CLI verbs.
4. **Correction/annotation sketch** — specify, before implementing, how to represent false positives, known special periods, camera rename corrections, and “do not surface” preferences without mutating raw evidence.
5. **Privacy join policy** — document default exclusions: no video, no thumbnails, no cross-domain joins by default, no behavioral/personality claims.
6. **Finding lifecycle metadata** — ensure every finding carries model version, generated-at, training/scoring windows, and source event range.

## Privacy, agency, and anti-creepy guardrails

`protect-cadence` deals with household surveillance-adjacent data. Its pattern-intelligence contract should be stricter than `clime` or `paprika-pantry`.

- Treat cameras as sensors, not personal dossiers.
- Never provide live video, clips, thumbnails, or face-level media surfaces to normal LLM reasoning.
- Do not infer mood, relationships, safety, identity, work habits, or private behavior from detection patterns.
- Avoid over-joining. Camera data should not silently combine with Swarm, Paprika, calendar, or messages just because the local data exists.
- Use “attention candidate,” “relative to this baseline,” and “drill down if needed” language rather than anomaly/suspicion language.
- Let humans correct source/model problems without rewriting raw observations: false positive, wrong camera/kind, known delivery/guest/travel period, maintenance day, camera moved/renamed.
- Keep corrections scoped. “Do not mention driveway package findings unless asked” is different from deleting package evidence.
- Preserve read-only inspectability: derived model DBs may be rebuilt, but source evidence should remain traceable.

## Success test

A good pattern-intelligence answer using `protect-cadence` should be able to answer:

- what bounded activity evidence exists?
- how fresh is it?
- what model run produced a finding?
- what baseline made it attention-worthy?
- which episodes/events support it?
- what is explicitly outside scope?
- how can a human inspect or correct the model?

If the Datasette/exploration surface can debug the pipeline while the stable verb/evidence-substrate surface keeps normal Robut answers bounded, private, and non-creepy, `protect-cadence` is carrying the right part of the broader pattern-intelligence architecture.
