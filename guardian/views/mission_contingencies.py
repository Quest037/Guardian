import tkinter as tk

from guardian.views.common import section_card

TITLE = "Mission Contingencies"
SUBTITLE = "Define fallback actions for mission risks and failures."


def build(parent: tk.Frame, palette: dict[str, str]) -> None:
    section_card(
        parent,
        palette,
        "Risk Matrix",
        "List potential failures and map each to fallback procedures.",
    ).pack(fill=tk.X, pady=(0, 10))
    section_card(
        parent,
        palette,
        "Automatic Responses",
        "Design auto-triggered responses when thresholds are exceeded.",
    ).pack(fill=tk.X)
