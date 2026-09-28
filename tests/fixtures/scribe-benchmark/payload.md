# Scribe Benchmark Payload: Research Stage Record

Synthetic stage-record payload, shaped like what a Squad Coordinator hands the Squad
Scribe after a research stage completes on the `rp-fixture-01` topic. Public,
synthetic content only — no private guide text. Used by `tests/tier0/Performance.Tests.ps1`
to simulate a Scribe write against `tests/fixtures/scribe-benchmark/seed/` and by
`scripts/Test-SquadScribeOutput.ps1`'s own fixture-driven smoke test.

## 1. History payload (Step 2 + Step 7, inseparable)

* Agent: Squad Researcher
* Member Name: Alpha
* Request: "Survey the fixture-topic's existing conventions and report the shape a
  synthetic harness fixture should follow."
* Deliverable: `research/2026-09-27-fixture-topic.md` (~1,800 words)
* Outcome: "Surveyed three comparable fixtures and recommended a minimal seed shape."
* Timestamp: 2026-09-27T10:00:00Z
* Turn: 2

### Consumption payload

```json
{
  "model": "Claude Sonnet 4.6",
  "model_source": "session-inherited",
  "priced_as": "Claude Sonnet 4.6",
  "model_tier": "default",
  "internal_turns": 12,
  "input_tokens": 9600,
  "cached_tokens": 38400,
  "cache_write_tokens": 8000,
  "output_tokens": 15000,
  "basis": "estimated"
}
```

## 2. Decision payload

* Decision: "Adopt the two-role (researcher, scribe) minimal fixture shape for the
  Scribe benchmark rather than the full 32-role profile."
* Rationale: "A full profile adds no coverage the write-completeness checks need and
  triples the fixture's maintenance surface."
* Turn: 2
* Architecturally Significant: no
* Timestamp: 2026-09-27T10:05:00Z

## 3. Orchestration payload (Squad Scribe's own turn)

* Deliverable: `decisions.md`, `state.json`, `consumption.md`, `history/Squad Researcher.md` (this turn's writes)
* Outcome: "Recorded the research-stage history entry, the fixture-shape decision, and advanced state."
* Timestamp: 2026-09-27T10:05:30Z
* Turn: 2

### Consumption payload — Orchestration

```json
{
  "model": "Claude Haiku 4.5",
  "model_source": "agent-pinned",
  "priced_as": "Claude Haiku 4.5",
  "model_tier": "fast",
  "internal_turns": 4,
  "input_tokens": 3000,
  "cached_tokens": 12000,
  "cache_write_tokens": 1250,
  "output_tokens": 3200,
  "basis": "estimated"
}
```

## 4. State advance

* turn: 1 → 2
* updated: 2026-09-27T10:05:30Z
* activeRoles: [] → ["Squad Researcher"]
* schemaVersion: unchanged (1.4)
