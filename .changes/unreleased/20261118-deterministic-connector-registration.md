---
bump: patch
type: Added
---

- **Connector bindings can now be registered without a Scribe model dispatch.** `Register-SquadConnector.ps1` validates and previews confirmed 1.1 replace/add registrations, then applies them transactionally with replay protection, rollback, preserved accounting/history, and bilingual registration guidance.
