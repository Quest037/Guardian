import tkinter as tk

from guardian.views.common import section_card

TITLE = "Create Mission"
SUBTITLE = "Define a new mission and assign devices."


def build(parent: tk.Frame, palette: dict[str, str]) -> None:
    section_card(
        parent,
        palette,
        "Mission Blueprint",
        "Set mission name, objective, timeline, and target device groups.",
    ).pack(fill=tk.X, pady=(0, 10))
    section_card(
        parent,
        palette,
        "Initial Checks",
        "Run readiness checks before the mission enters planning.",
    ).pack(fill=tk.X)
