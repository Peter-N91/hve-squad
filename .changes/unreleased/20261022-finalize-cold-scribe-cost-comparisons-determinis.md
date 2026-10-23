---
bump: patch
type: Fixed
---

- **Cold Scribe accounting no longer requires hand-calculated comparison repairs after verification.** The ledger helper now finalizes and checks estimated cost, credits and signed savings transactionally, preserves supplied baseline assumptions and notes, and keeps observed host billing separate. Ordinary handoffs reuse the same calculation; missing baselines remain explicitly unavailable.
