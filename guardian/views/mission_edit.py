import tkinter as tk

from guardian.views.common import section_card

TITLE = "Edit Mission"
SUBTITLE = "Adjust mission settings safely before execution."


def build(parent: tk.Frame, palette: dict[str, str]) -> None:
    section_card(
        parent,
        palette,
        "Revision Controls",
        "Track mission version history and modify device allocations.",
    ).pack(fill=tk.X, pady=(0, 10))
    section_card(
        parent,
        palette,
        "Approval Workflow",
        "Require operator sign-off before publishing mission updates.",
    ).pack(fill=tk.X)
