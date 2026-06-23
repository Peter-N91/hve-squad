<!-- markdownlint-disable-file MD041 -- GitHub PR templates are injected verbatim into the PR description, so they cannot start with a top-level heading or YAML frontmatter. -->
<!--
Title convention: release: vX.Y.Z   (for releases)
                  type(scope): short description   (for regular changes)
-->

## Summary

<!-- One or two lines describing what this PR does. -->

## Target version

- Target version: **vX.Y.Z**
- Previous version: vX.Y.Z

## Type of change

- [ ] Release (version bump)
- [ ] Feature / new content
- [ ] Fix
- [ ] Docs only
- [ ] Chore / maintenance

## Shared learning sanitization (if proposing a learning)

<!-- Complete only if this PR adds or edits squad-src/.github/skills/squad/learnings/shared-learnings.md. -->

- [ ] Remove all secrets, tokens, credentials, and connection strings.
- [ ] Remove customer, organization, and individual names.
- [ ] Remove repository-specific absolute paths and internal URLs.
- [ ] Generalize stack-specific or environment-specific details so the learning applies beyond its origin.
- [ ] Confirm the learning is broadly applicable across consumers and scenarios.

## Changelog

- [ ] `CHANGELOG.md` has a `## [X.Y.Z]` section describing this release
- [ ] `apm.yml` `version:` is bumped to match (release PRs only)

## Release checklist (release PRs only)

- [ ] Branch named `release/vX.Y.Z`
- [ ] PR title is `release: vX.Y.Z`
- [ ] After merge, tag the merge commit: `git tag -a vX.Y.Z -m "Release vX.Y.Z"`
- [ ] Push the tag: `git push origin vX.Y.Z`
- [ ] (Optional) Publish a GitHub Release for the tag

## Notes

<!-- Anything reviewers should know: follow-ups, risks, manual steps. -->
