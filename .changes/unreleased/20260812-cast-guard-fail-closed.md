---
bump: patch
type: Fixed
---

- **The upstream cast guard reported a clean verdict on a breaking change, and released it.**
  `v0.12.9` moved the hve-core pin across a commit that removed seven agents the squad still binds —
  `ADO Backlog Manager`, `AzDO PRD to WIT`, `GitHub Backlog Manager`, `Jira Backlog Manager`,
  `Jira PRD to WIT`, `Agile Coach`, and `Product Manager Advisor`, the whole `product-owner` cast —
  plus eighteen backlog prompts. The guard ran, listed every removal correctly, and still concluded
  `non-breaking`. The cross-check that decides the verdict resolved `squad-src` as a **path relative
  to the working directory** and enumerated it with `Get-ChildItem -Include`, which matched nothing
  on the Linux runner while working locally on Windows; every other section of the same brief read
  from an absolute path and was correct. `Get-SquadReferenceCount` now anchors the squad source on
  the script's own location so the scan cannot depend on the caller's directory, and filters
  extensions explicitly instead of relying on `-Include` against a directory
  (`scripts/Get-HveCoreCastDelta.ps1`).
- **Two independent fail-open paths let the silent zero reach a release tag.** The script returned
  `Count = 0` when it could not read the squad source, making "cannot check" indistinguishable from
  "nothing references it"; and every bump step in the sync workflow gated on
  `is_breaking != 'true'`, which is equally satisfied by `false`, by an empty string, by an unset
  output, and by a guard step that never ran. Either one alone would have stopped the release. The
  script now **throws** when the squad source is missing or the scan enumerates no files, and the
  workflow gates on `is_breaking == 'false'`, so only an explicit non-breaking verdict may release
  (`scripts/Get-HveCoreCastDelta.ps1`, `.github/workflows/sync-hve-core.yml`).
