---
bump: patch
type: Security
---

- Improve Checkov and Zizmor scan summaries with severity counts and details about accepted findings. Justified Checkov suppressions are filtered from GitHub Code Scanning while the full results remain available, and Zizmor SARIF output is retained as a downloadable artifact.
- **Security scan summary and reporting improvements:**
    The Checkov workflow now generates a summary table with counts by severity (errors, warnings, notes, suppressed), and includes details about suppressed findings (rule, location, justification) in a collapsible section of the summary.
    The Zizmor workflow outputs a similar summary with severity counts and a breakdown of findings by rule, severity, and confidence. Suppressed findings are counted based on inline ignore comments.

- **SARIF output handling and artifact retention:**
    For Checkov, suppressed findings (those with justifications) are filtered out before uploading to GitHub Code Scanning, so only actionable alerts appear in the Security tab. The full SARIF output, including suppressed findings, is retained as a downloadable artifact.
    For Zizmor, the SARIF output is uploaded both to GitHub Code Scanning and as an artifact for later review.