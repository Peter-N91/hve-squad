---
bump: patch
type: Added
---

- **Squad Doctor is a dedicated post-upgrade and runtime-recovery agent.** Both plugin and APM entrypoints use deterministic checks, explicit repair approval, shared writer locks, backups, and verification through `Invoke-SquadDoctor.ps1`. Missing or invalid rate tables have a scripted repair; unsupported faults remain explicit blockers. Coordinators can invoke Doctor without relying on a healthy roster.
