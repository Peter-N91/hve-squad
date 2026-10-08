# Blind Judge Rubric

You are grading anonymised deliverables. Each `samples/S<n>.diff` is the full change one
run made to the same starting repository for the task in `task.md`. Samples are shuffled
and stripped of anything identifying how they were produced. Grade only what is in the
diff; do not guess its origin.

Score every sample on four criteria, each an integer 1-10 with a one-line reason:

| Criterion   | 10 means                                                                                       | 1 means                                              |
| ----------- | ---------------------------------------------------------------------------------------------- | ---------------------------------------------------- |
| correctness | Every requirement in `task.md` is met, edge cases handled, existing behaviour kept              | Requirements missed or behaviour broken              |
| tests       | Tests would fail on a plausible wrong implementation, cover the edge cases, and are deterministic | No tests, tests that cannot fail, or flaky tests     |
| design      | Simple, robust, idiomatic; no needless code, scratch files, or hidden coupling                  | Fragile, over-built, or leaves stray artefacts       |
| docs        | Requested docs are accurate, specific, and correct about the failure and the fix               | Docs missing, wrong, or vague                        |

When `task.md` requests no documentation, set `docs` to `null`.

Grade each sample independently against this rubric, not against the other samples. Read
every sample before scoring any.

Reply with exactly one JSON object and nothing else, in this shape:

```json
{"samples":[{"id":"S1","correctness":{"score":8,"reason":"..."},"tests":{"score":7,"reason":"..."},"design":{"score":8,"reason":"..."},"docs":{"score":6,"reason":"..."}}]}
```
