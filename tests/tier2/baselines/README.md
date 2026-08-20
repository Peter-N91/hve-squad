# Tier 2 golden baselines

One `<scenario>.baseline.json` per Tier 1 scenario, captured from a release known to be
good. Each is a Tier 1 observation: the roles that ran, the deliverable roots and types
that landed, the gate verdicts that fired, and the answer the run gave.

## Capturing

Capture only from a run whose Tier 0 and Tier 1 results were green. A baseline taken
from a broken run makes every later comparison agree with the break, which is worse than
having no baseline at all — the suite would then report calm while the defect ships.

```pwsh
./tests/tier1/Invoke-Tier1LiveRun.ps1 -Ref v0.16.0
./tests/tier2/Compare-SquadRun.ps1 -ObservationRoot ./tests/tier1/results -UpdateBaseline
```

Commit the result, and say in the commit message which ref it came from.

## Re-capturing

Re-capture when an intended change moves a roster, a deliverable root, or a gate. Do not
re-capture to silence a difference you have not explained: an unexplained difference is
the signal this tier exists to produce.
