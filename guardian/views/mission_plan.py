import tkinter as tk

from guardian.views.common import section_card

TITLE = "Plan Mission"
SUBTITLE = "Coordinate sequencing and timing for multi-device control."


def build(parent: tk.Frame, palette: dict[str, str]) -> None:
    section_card(
        parent,
        palette,
        "Timeline",
        "Configure mission phases, timing offsets, and synchronization points.",
    ).pack(fill=tk.X, pady=(0, 10))
    section_card(
        parent,
        palette,
        "Resource Planner",
        "Allocate operators, fallback devices, and communication channels.",
    ).pack(fill=tk.X)
