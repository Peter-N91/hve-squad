---
bump: minor
type: Added
---

- Opt-in capability-ranked model routing with `routing=ranked`
- Squad Scribe hot/cold reference split: about 7% fewer reference bytes read per history write (computed); no wall-clock improvement was demonstrated (see [ADR-0007](docs/architecture/adr/0007-capability-ranked-model-routing-and-scribe-ledger-determinism.md))
- Optional deterministic ledger helper `Measure-SquadLedger.ps1` (PowerShell 7+, read-only)
- Coordinator runs the optional read-only ledger check after Scribe writes when PowerShell 7+ is available, instead of trusting the Scribe's self-report
- Default behavior unchanged when no policy is supplied
