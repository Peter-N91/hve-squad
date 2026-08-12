---
bump: patch
type: Fixed
---

- **The cast guard could not see `squad-src/` on the runner, because Linux hides dot-directories.**
  Every file in `squad-src/` lives under `.github/`, and a dot-prefixed entry is hidden on Linux, so
  the `Get-ChildItem -Recurse` behind the reference cross-check never descended past `squad-src/`
  and found zero references to anything. Windows has no dot-file convention, so the identical scan
  matched all 53 files on a developer machine — which is why `v0.12.9` shipped a pin that removed
  the entire `product-owner` cast while the guard reported `non-breaking`, and why nobody could
  reproduce it locally. The scan now passes `-Force`
  (`scripts/Get-HveCoreCastDelta.ps1`).
- **The fail-closed guard did its job on first contact.** The preceding release turned the silent
  zero into a hard stop, and the next manual run failed at the guard with `contains no .md or .yml
  files` instead of quietly releasing. That failure is what identified the real cause; a guard that
  refuses to answer when it cannot read its input is worth more than one that guesses.
