"""Azure internal web app LLD diagram (reference template).

Renders a low-level design diagram with real Azure icons for an internal
web app baseline: two App Service apps (frontend + backend), private Azure
SQL and Storage, Key Vault via managed identity, a VNet with integration
and private-endpoint subnets, and Log Analytics diagnostics.

This file is a documentation-only reference template. Copy it into a
consumer repo (for example ``docs/architecture/azure_webapp_lld.py``),
adjust the nodes and edges to match that project's Bicep or Terraform
modules, then run it to emit paired PNG + SVG output::

    python azure-webapp-lld.py

Prerequisites:
    * ``pip install -r requirements.txt`` (the ``diagrams`` package).
    * Graphviz ``dot`` on PATH (``winget install Graphviz.Graphviz``).
"""

from __future__ import annotations

import sys
from pathlib import Path

# Make the shared diagram_io helper importable whether this file runs from
# the skill's templates/ folder or from a copy placed beside scripts/.
_SCRIPTS = Path(__file__).resolve().parent.parent / "scripts"
if _SCRIPTS.is_dir():
    sys.path.insert(0, str(_SCRIPTS))
else:
    sys.path.insert(0, str(Path(__file__).resolve().parent))

from diagrams import Cluster, Diagram, Edge  # noqa: E402
from diagrams.azure.analytics import LogAnalyticsWorkspaces  # noqa: E402
from diagrams.azure.compute import AppServices  # noqa: E402
from diagrams.azure.database import SQLDatabases  # noqa: E402
from diagrams.azure.network import PrivateEndpoint, VirtualNetworks  # noqa: E402
from diagrams.azure.security import KeyVaults  # noqa: E402
from diagrams.azure.storage import StorageAccounts  # noqa: E402
from diagrams.onprem.client import Users  # noqa: E402

from diagram_io import diagram_kwargs  # noqa: E402


def main() -> None:
    """Render the LLD diagram into the directory containing this script."""
    outdir = Path(__file__).resolve().parent
    with Diagram(
        "Azure Internal Web App - LLD (West Europe)",
        **diagram_kwargs("azure-webapp-lld", direction="LR", outdir=outdir),
    ):
        user = Users("Internal user")
        logs = LogAnalyticsWorkspaces("Log Analytics")

        with Cluster("VNet"):
            with Cluster("Integration subnet"):
                frontend = AppServices("Frontend App Service\n(Entra ID)")
                backend = AppServices("Backend App Service\n(Managed identity)")
            with Cluster("Private-endpoints subnet"):
                sql_pe = PrivateEndpoint("SQL PE")
                storage_pe = PrivateEndpoint("Storage PE")
                kv_pe = PrivateEndpoint("Key Vault PE")

        sql = SQLDatabases("Azure SQL (Basic)")
        storage = StorageAccounts("Storage")
        keyvault = KeyVaults("Key Vault")

        user >> Edge(label="HTTPS / Entra ID") >> frontend
        frontend >> Edge(label="HTTPS") >> backend
        backend >> Edge(label="Managed identity") >> kv_pe >> keyvault
        backend >> Edge(label="Private link") >> sql_pe >> sql
        backend >> Edge(label="Private link") >> storage_pe >> storage

        for node in (frontend, backend, sql, storage, keyvault):
            node >> Edge(style="dotted", label="diagnostics") >> logs


if __name__ == "__main__":
    main()
