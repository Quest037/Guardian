import tkinter as tk

from guardian.views.common import section_card

TITLE = "Devices"
SUBTITLE = "Add and remove devices under HQ control."


def build(parent: tk.Frame, palette: dict[str, str]) -> None:
    section_card(
        parent,
        palette,
        "Device Registry",
        "Register new devices, remove retired units, and track per-device metadata.",
    ).pack(fill=tk.X, pady=(0, 10))
    section_card(
        parent,
        palette,
        "Bulk Actions",
        "Queue add/remove operations for multiple devices in one action set.",
    ).pack(fill=tk.X)
