import tkinter as tk

from guardian.views.common import section_card

TITLE = "Calibrate Devices"
SUBTITLE = "Prepare selected devices with calibration profiles."


def build(parent: tk.Frame, palette: dict[str, str]) -> None:
    section_card(
        parent,
        palette,
        "Calibration Queue",
        "Create repeatable calibration runs and apply them to one or many devices.",
    ).pack(fill=tk.X, pady=(0, 10))
    section_card(
        parent,
        palette,
        "Validation",
        "Show pass/fail metrics and mark devices as mission-ready.",
    ).pack(fill=tk.X)
