---
bump: patch
type: Fixed
---

- **The Tier 1 contract could not read a single real token rate.** The rate reader matched a model
  name with `[A-Za-z0-9._-]+`, which excludes the space in `Claude Sonnet 4.6`, and then read the
  four rate columns by position on a table that carries `Tier` and `Notes` around them. Fed the
  shipped `consumption-rates.md` template it parsed zero rows, so every "rates match
  consumption-rates.md" case compared against an empty collection and reported the squad broken when
  the reader was. Tables are now selected by their column headers and cells read by name, which also
  keeps the dispatch-size estimator's class rows — five numeric-looking columns — from registering as
  prices (`tests/tier1/SquadState.psm1`).
- **The self-check was validating the fixture, not the product.** `SquadFixture.psm1` wrote its own
  five-column rate table with a hyphenated model name, so the reader passed 11 of 11 mutations while
  being unable to read the file a real squad seeds. The fixture now lifts the rate table out of the
  shipped skill, and a mutation breaks a column header to prove an unreadable table fails loudly
  (`tests/tier1/SquadFixture.psm1`, `tests/tier1/Assertions.Tests.ps1`,
  `tests/tier1/StateContract.Tests.ps1`).
- **The run-total assertion could not pass on a correct ledger.** One tolerance of `0.001` was
  applied to a total the template prints at two decimals, so a ledger summing to `2.04684` and
  printing `$2.05` failed by `0.00316` for following its own template. Ledger figures are now
  compared against the sum rounded to the precision the ledger printed, which is exact rather than
  tolerant and still catches the dropped roles the case exists for
  (`tests/tier1/SquadState.psm1`, `tests/tier1/StateContract.Tests.ps1`).
- **Two squad rules had no assertion behind them.** History files were checked for a heading and a
  consumption block but never for a name that resolves to a roster row, and nothing asserted that
  Init leaves `history/` empty — so a squad that seeded a header-only file per member passed its
  Init scenario and only failed a turn later, for a different reason. Both are now contract cases
  with mutation controls (`tests/tier1/StateContract.Tests.ps1`, `tests/tier1/Assertions.Tests.ps1`).
