---
description: "Append-only dispatch history for a single squad agent"
---

# History: Legacy Agent

### 2026-09-20T09:00:00Z Bad-fence consumption block (single backtick, not triple)

* Turn: 1
* Request: Synthetic fixture entry exercising a bad code fence.
* Deliverable: `fixtures/ledger-baseline/legacy-1.md`
* Outcome: Synthetic.

#### Consumption

`json
{
  "model": "Claude Sonnet 4.6",
  "model_source": "session-inherited",
  "priced_as": "Claude Sonnet 4.6",
  "model_tier": "default",
  "internal_turns": 1,
  "input_tokens": 100,
  "cached_tokens": 0,
  "cache_write_tokens": 0,
  "output_tokens": 50,
  "basis": "estimated"
}
`

### 2026-09-20T09:05:00Z Table-instead-of-JSON consumption block

* Turn: 1
* Request: Synthetic fixture entry pasting a markdown table where JSON belongs.
* Deliverable: `fixtures/ledger-baseline/legacy-2.md`
* Outcome: Synthetic.

#### Consumption

| model              | model_source      | priced_as          | internal_turns |
| ------------------ | ------------------ | ------------------- | --------------- |
| Claude Sonnet 4.6   | session-inherited  | Claude Sonnet 4.6   | 1                |

### 2026-09-20T09:10:00Z Illegal model_source consumption block

* Turn: 1
* Request: Synthetic fixture entry with an illegal model_source value.
* Deliverable: `fixtures/ledger-baseline/legacy-3.md`
* Outcome: Synthetic.

#### Consumption

```json
{
  "model": "Claude Sonnet 4.6",
  "model_source": "session",
  "priced_as": "Claude Sonnet 4.6",
  "model_tier": "default",
  "internal_turns": 1,
  "input_tokens": 100,
  "cached_tokens": 0,
  "cache_write_tokens": 0,
  "output_tokens": 50,
  "basis": "estimated"
}
```

### 2026-09-20T09:15:00Z Newline/whitespace-split priced_as consumption block

* Turn: 1
* Request: Synthetic fixture entry whose priced_as carries surrounding whitespace.
* Deliverable: `fixtures/ledger-baseline/legacy-4.md`
* Outcome: Synthetic.

#### Consumption

```json
{
  "model": "Claude Opus 5",
  "model_source": "agent-pinned",
  "priced_as": " Claude Opus 5 ",
  "model_tier": "extended",
  "internal_turns": 1,
  "input_tokens": 100,
  "cached_tokens": 0,
  "cache_write_tokens": 0,
  "output_tokens": 50,
  "basis": "estimated"
}
```

### 2026-09-20T09:20:00Z Well-formed consumption block (baselined)

* Turn: 2
* Request: Synthetic fixture entry that is entirely well-formed.
* Deliverable: `fixtures/ledger-baseline/legacy-5.md`
* Outcome: Synthetic.

#### Consumption

```json
{
  "model": "Claude Sonnet 4.6",
  "model_source": "session-inherited",
  "priced_as": "Claude Sonnet 4.6",
  "model_tier": "default",
  "internal_turns": 2,
  "input_tokens": 200,
  "cached_tokens": 0,
  "cache_write_tokens": 0,
  "output_tokens": 100,
  "basis": "estimated"
}
```
