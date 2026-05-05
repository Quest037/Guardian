import tkinter as tk

from guardian.views.common import section_card

TITLE = "Position Devices"
SUBTITLE = "Set and fine-tune individual device placement."


def build(parent: tk.Frame, palette: dict[str, str]) -> None:
    section_card(
        parent,
        palette,
        "Placement Controls",
        "Adjust position, orientation, and zone assignment for each device.",
    ).pack(fill=tk.X, pady=(0, 10))
    section_card(
        parent,
        palette,
        "Map Preview",
        "Reserve this area for a visual layout/map in the next iteration.",
    ).pack(fill=tk.X)
