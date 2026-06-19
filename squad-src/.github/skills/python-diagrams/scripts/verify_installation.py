"""Verify the python-diagrams toolchain is installed and rendering.

Checks two things the skill depends on:

1. The Python ``diagrams`` package (and its Azure node set) imports.
2. Graphviz's ``dot`` binary is on PATH and can render a trivial diagram.

Run::

    python verify_installation.py

Exits ``0`` when both checks pass, ``1`` otherwise with remediation hints.
"""

from __future__ import annotations

import sys
import tempfile
from pathlib import Path


def main() -> int:
    """Run the import and render checks; return a process exit code."""
    try:
        from diagrams import Diagram
        from diagrams.azure.compute import AppServices
    except ImportError as exc:
        print(f"FAIL: python 'diagrams' package not importable: {exc}")
        print("Fix: pip install -r requirements.txt")
        return 1

    try:
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "verify"
            with Diagram("verify", filename=str(out), outformat="png", show=False):
                AppServices("probe")
            if not out.with_suffix(".png").exists():
                print("FAIL: render produced no PNG (is Graphviz 'dot' installed?)")
                return 1
    except Exception as exc:  # noqa: BLE001 - surface any render failure to the user
        print(f"FAIL: render failed (Graphviz 'dot' missing or broken?): {exc}")
        print("Fix: install Graphviz and reopen the shell, e.g. winget install Graphviz.Graphviz")
        return 1

    print("OK: 'diagrams' imports and Graphviz rendered a test PNG.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
