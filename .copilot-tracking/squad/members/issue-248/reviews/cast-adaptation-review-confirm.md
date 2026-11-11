# Cast Adaptation Review: Third Confirmation Pass (issue-248)

Verdict: approve

Scope: confirmation of the Follow-up 2 troubleshooting-table cleanup in `docs/demo-3.html` and `docs/fr/demo-3.html`, plus a repo-wide residual `presenter` sweep, release-hygiene checks, and fragment count. No implementation file was modified. No git commit, push, or gh command was run.

## 1. Troubleshooting rows (fixed lines, verbatim)

`docs/demo-3.html:248`

```html
<tr><td>A role does not dispatch</td><td>Confirm the agent it maps to is installed — the <code>product</code> profile resolves <code>analyst</code>, <code>designer</code>, <code>product-owner</code>, <code>experimenter</code>, and <code>technical-writer</code> to deployed HVE Core agents (the <code>presenter</code> role was removed with hve-core f425e94).</td></tr>
```

`docs/fr/demo-3.html:259`

```html
<tr><td>Un rôle n'est pas sollicité</td><td>Vérifiez que l'agent auquel il correspond est installé — le profil <code>product</code> associe <code>analyst</code>, <code>designer</code>, <code>product-owner</code>, <code>experimenter</code> et <code>technical-writer</code> aux agents HVE Core déployés (le rôle <code>presenter</code> a été supprimé avec hve-core f425e94).</td></tr>
```

Result: pass. Neither row lists `presenter` as a currently-resolved role. Both mention it only as removed.

## 2. Residual `presenter` sweep (squad-src/, docs/, tests/)

Every hit is a historical or removal note:

| Location | Classification |
|---|---|
| `squad-src/.github/instructions/squad/squad-autopilot.instructions.md:71` | Removal note |
| `squad-src/.github/instructions/squad/pptx-brand-template.instructions.md:8` | Removal note ("no longer has a `presenter` role") |
| `docs/usage.html:1751`, `docs/fr/usage.html:1751` | Removal note |
| `docs/demo-3.html:207`, `docs/fr/demo-3.html:216` | Removal note, historical walkthrough |
| `docs/demo-3.html:248`, `docs/fr/demo-3.html:259` | Removal parenthetical (see section 1) |
| `tests/tier0/Performance.Tests.ps1:354` | Code comment recording the removal |

Result: pass. No hit asserts that the role is available.

## 3. Release hygiene

* `CHANGELOG.md`: not modified (`git status` shows no entry).
* `apm.yml` version line: `version: 0.20.0` at HEAD and in the working tree. Unchanged.
* `apm.yml` does show modifications. These are the hve-core dependency pin moves (`#1707282…` → `#f425e94…`), which the change record documents. They are outside the version-line check and were not evaluated as a release bump.

Result: pass.

## 4. Changelog fragments

`.changes/unreleased/` contains exactly one fragment, `20261110-adapt-squad-cast-to-hve-core-f425e94.md`, with `bump: minor`. The `.gitkeep` file is not a fragment.

Result: pass.

## Overall

All four checks pass. Verdict: approve.
