"""Shared output helpers for the python-diagrams skill.

Every diagram generator imports from this module instead of configuring
output formats inline, so all artifacts follow the same dual-output
contract: each diagram is rendered as a paired PNG and SVG sibling. This
mirrors the reference-template-in-a-skill pattern used elsewhere in the
squad package and keeps rendered evidence diffable and review-friendly.

Usage::

    from diagrams import Diagram
    from diagram_io import diagram_kwargs

    with Diagram("My architecture", **diagram_kwargs("01-architecture", direction="LR")):
        ...  # nodes and edges
"""

from __future__ import annotations

from pathlib import Path
from typing import Any

# Formats every generator emits, in render order.
DUAL_OUTPUT_FORMATS: list[str] = ["png", "svg"]


def diagram_kwargs(
    base_name: str,
    *,
    direction: str = "LR",
    outdir: str | Path = ".",
    show: bool = False,
) -> dict[str, Any]:
    """Build keyword arguments for :class:`diagrams.Diagram`.

    Args:
        base_name: File stem for the rendered diagram, without an extension.
        direction: Graph layout direction (``"LR"``, ``"TB"``, ``"RL"``, ``"BT"``).
        outdir: Directory the paired PNG and SVG siblings are written to;
            created if it does not exist.
        show: Whether to open the rendered diagram after generation. Defaults
            to ``False`` so generators stay headless and CI-safe.

    Returns:
        A mapping suitable for ``Diagram(title, **diagram_kwargs(...))`` that
        renders paired PNG and SVG output into ``outdir``.
    """
    out = Path(outdir)
    out.mkdir(parents=True, exist_ok=True)
    return {
        "filename": str(out / base_name),
        "outformat": list(DUAL_OUTPUT_FORMATS),
        "show": show,
        "direction": direction,
    }
