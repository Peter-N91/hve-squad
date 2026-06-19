---
name: python-diagrams
description: 'Documentation-only reference template for rendering Azure architecture diagrams with real product icons using the Python `diagrams` library (Graphviz backend), producing paired PNG + SVG output. Use when a squad role needs a committed, file-based icon diagram (HLD/LLD) instead of Mermaid, especially for the Squad Azure Architect. Templates never run from this package; a consumer copies them on demand.'
license: MIT
metadata:
  authors: "Peter-N91/hve-squad"
  spec_version: "1.0"
  last_updated: "2026-06-19"
---

# Python Diagrams

## Overview

This skill bundles a **documentation-only reference template** for rendering Azure architecture
diagrams with real Azure product icons using the Python [`diagrams`](https://diagrams.mingrammer.com/)
library on a Graphviz backend. It is the **file-based, committed-artifact** counterpart to the squad's
Mermaid default and the interactive `drawio` MCP path: where Mermaid renders inline and draw.io opens
an editor, this skill writes paired `.png` + `.svg` siblings straight into the consumer repo.

Like every other reference template in the squad package (see `.github/skills/azure-scaffold/` and
`.github/skills/squad/`), **nothing here runs from the package**. The consumer copies a generator into
their repo, adjusts it to match their Bicep or Terraform modules, and runs it. The package never reads
or writes the consumer's source tree.

This skill backs the `diagram-rendering` capability's non-MCP, file-output option documented in
[`squad-mcp-capability.instructions.md`](../../instructions/squad/squad-mcp-capability.instructions.md)
(*"Out-of-Band Fallbacks → Python `diagrams` Library"*). The library is the integration surface; no
`.vscode/mcp.json` entry is required.

## When to use

* A role (typically the **Squad Azure Architect**) needs an HLD or LLD diagram with **Azure icons**
  persisted as a committed image, not an inline Mermaid block or a browser-only draw.io tab.
* You want the diagram to live next to the IaC and stay diffable in version control.

Does **not**: produce Mermaid (author that inline), drive the `drawio` MCP (that is the interactive
draw.io path), generate Bicep/Terraform, or deploy anything.

## Bundled files

| File                                                       | Consumer destination (suggested)                       | Purpose                                                                 |
|------------------------------------------------------------|--------------------------------------------------------|-------------------------------------------------------------------------|
| [requirements.txt](requirements.txt)                       | merged into the repo's Python deps                     | Pins `diagrams` and `graphviz`; notes the Graphviz system prerequisite. |
| [scripts/diagram_io.py](scripts/diagram_io.py)             | beside each generator (or on `sys.path`)               | Shared output helper enforcing the paired PNG + SVG dual-output contract. |
| [scripts/verify_installation.py](scripts/verify_installation.py) | run once after install                            | Confirms `diagrams` imports and Graphviz `dot` renders.                 |
| [templates/azure-webapp-lld.py](templates/azure-webapp-lld.py)  | `docs/architecture/azure_webapp_lld.py`           | Azure internal web app LLD generator with real Azure icons.             |

## Prerequisites

1. **Graphviz** (system binary, not pip-installable) on PATH:
   * Windows: `winget install Graphviz.Graphviz` (machine-scope; run elevated, then reopen the shell)
   * macOS: `brew install graphviz`
   * Linux: `apt-get install graphviz`
2. **Python packages**: `pip install -r requirements.txt` (or `uv run --with diagrams ...`).

Verify both with `python scripts/verify_installation.py`.

## Usage

1. Copy `scripts/diagram_io.py` and a generator from `templates/` into the consumer repo (for an LLD,
   copy `templates/azure-webapp-lld.py` next to `diagram_io.py` under `docs/architecture/`).
2. Edit the generator's nodes and edges to match the project's actual Bicep or Terraform modules.
3. Run it: `python azure-webapp-lld.py` (or `uv run --with diagrams python azure-webapp-lld.py`).
4. Commit the emitted `azure-webapp-lld.png` and `.svg`.

## Dual-output contract

Every generator imports `diagram_kwargs` from `diagram_io` instead of setting `outformat` inline, so
all diagrams render **both** a PNG and an SVG sibling with consistent naming. This keeps a
review-friendly raster (PNG) and a scalable vector (SVG) in sync from a single source of truth.

```python
from diagrams import Diagram
from diagram_io import diagram_kwargs

with Diagram("My architecture", **diagram_kwargs("01-architecture", direction="LR")):
    ...  # nodes and edges
```

## Azure node reference

Import the specific node class per resource; common Azure nodes used by the web app template:

```python
from diagrams.azure.compute import AppServices
from diagrams.azure.database import SQLDatabases
from diagrams.azure.network import VirtualNetworks, PrivateEndpoint, Subnets
from diagrams.azure.security import KeyVaults
from diagrams.azure.storage import StorageAccounts
from diagrams.azure.analytics import LogAnalyticsWorkspaces
from diagrams.azure.identity import ManagedIdentities
```

The full Azure node catalog is at <https://diagrams.mingrammer.com/docs/nodes/azure>.

## Fallback ladder

Per the capability map, the `diagram-rendering` order is: a draw.io MCP when configured → this Python
`diagrams` library for committed image output → Mermaid in chat or repository markdown when neither is
available. A role never blocks on a missing tool; it falls back and records which path it took.
