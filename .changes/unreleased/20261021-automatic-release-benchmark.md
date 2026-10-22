---
bump: patch
type: Changed
---

- **Release gates on stored benchmark evidence and PRs to `main` get the same check.**
  Release and Release Prep compare the pushed stored benchmark records through the
  read-only recorded workflow, without paid collection or model secrets, and the
  same comparison now runs once per pull request to `main`, using the PR's base and
  head SHAs (fork heads fetched as objects only) and a per-PR concurrency group.
  The bounded paid collector stays available only through manual dispatch;
  its automatic release wiring is kept on a separate experimental branch.
  The explicit manual Release benchmark bypass remains available.
