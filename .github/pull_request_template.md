<!-- markdownlint-disable-file MD041 -- GitHub PR templates are injected verbatim into the PR description, so they cannot start with a top-level heading or YAML frontmatter. -->
<!--
Title convention: type(scope): short description
-->

## Summary

<!-- One or two lines describing what this PR does. -->

## Type of change

- [ ] Feature / new content
- [ ] Fix
- [ ] Docs only
- [ ] Chore / maintenance

## Change fragment

<!--
Do NOT edit CHANGELOG.md and do NOT bump `version:` in apm.yml. Both are
release outputs assembled on main, and editing them here is exactly what makes
concurrent pull requests conflict. CI rejects a PR that touches either.

Run `apm run change` to create your fragment. See .changes/README.md.
-->

- [ ] Added a fragment under `.changes/unreleased/` (`apm run change`)
- [ ] Its `bump` tracks ideas, not artifacts: `patch` unless this introduces a genuinely new idea (`minor`) or breaks consumers (`major`)
- [ ] Its body reads as final release notes, not as a commit message
- [ ] I did not edit `CHANGELOG.md` or `apm.yml` `version:`

<!--
A new agent, skill, or role that extends something already shipping is a patch,
however many files it adds. Minor is for the concept, not for the artifacts
built under it. When unsure, pick patch.

No consumer-visible change at all? Ask a maintainer for the `skip-changelog`
label instead. That skips the version bump too.
-->

## Tests

<!--
Major new functionality must come with tests. See "Automated tests" in
CONTRIBUTING.md. Declare the case in tests/squad-behavior-contract.md first,
then implement it in the matching tier.
-->

- [ ] Added or extended an automated test case for the behavior this PR changes, or this PR changes no observable behavior
- [ ] Declared the case in `tests/squad-behavior-contract.md` with an ID and a citation to the source file stating the rule
- [ ] Ran `apm run test` (Tier 0) locally and it passed

## Shared learning sanitization (if proposing a learning)

<!-- Complete only if this PR adds or edits squad-src/.github/skills/squad/learnings/shared-learnings.md. -->

- [ ] Remove all secrets, tokens, credentials, and connection strings.
- [ ] Remove customer, organization, and individual names.
- [ ] Remove repository-specific absolute paths and internal URLs.
- [ ] Generalize stack-specific or environment-specific details so the learning applies beyond its origin.
- [ ] Confirm the learning is broadly applicable across consumers and scenarios.

## Notes

<!-- Anything reviewers should know: follow-ups, risks, manual steps. -->
