import tkinter as tk

from guardian.views.common import section_card

TITLE = "End Mission"
SUBTITLE = "Close operations, archive outputs, and release devices."


def build(parent: tk.Frame, palette: dict[str, str]) -> None:
    section_card(
        parent,
        palette,
        "Shutdown Sequence",
        "Define safe mission stop procedures and staged device release.",
    ).pack(fill=tk.X, pady=(0, 10))
    section_card(
        parent,
        palette,
        "Post-Mission Report",
        "Generate summary artifacts and export mission outcome data.",
    ).pack(fill=tk.X)
