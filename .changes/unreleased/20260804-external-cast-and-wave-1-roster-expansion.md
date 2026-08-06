---
bump: minor
type: Added
---

- **The squad could only cast agents this package or hve-core already shipped.** An **external cast** now lets a role resolve to a public marketplace resource without copying it in. Resources arrive by one of two tiers: **bundled** ones are pinned `apm.yml` dependencies a consumer gets by installing hve-squad alone, and **opt-in** ones stay behind an `apm install` command so nobody carries a vertical they did not ask for. Every entry passes a verification gate before it is registered, rejections land on a blocklist, and `github/awesome-copilot` is attributed in NOTICE. The first bundled entry is the `azure-pricing` skill, wired into Squad Cost Manager (`squad-src/.github/instructions/squad/squad-roster.instructions.md`).
- **Two roles for capability that already shipped but was never cast.** `accessibility` assesses a product against WCAG 2.2, ARIA, Section 508, and EN 301 549 and discovers the surfaces that need assessing; `supply-chain` assesses how software is built, signed, and released against OpenSSF Scorecard, SLSA, Sigstore, and SBOM. Two new profiles package roles that already existed: `accessibility` and `modernization`.
- **The `full` profile did not contain everything it promised, and `privacy` was in no profile at all.** `full` now carries every role in the cast except the opt-in `backlog-executor` and the unbacked `devrel`, and `privacy` is seeded into `full` and `security`. GitLab, synthetic data, knowledge-graph research, and the code-review explainer and walkback agents each gained a route or a stated escalation.
