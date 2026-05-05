import tkinter as tk

from guardian.views.common import section_card

TITLE = "Live Mission Control"
SUBTITLE = "Operate many devices in real time during active missions."


def build(parent: tk.Frame, palette: dict[str, str]) -> None:
    section_card(
        parent,
        palette,
        "Live Commands",
        "Send synchronized commands to selected devices with confirmation feedback.",
    ).pack(fill=tk.X, pady=(0, 10))
    section_card(
        parent,
        palette,
        "Telemetry Stream",
        "Reserve this area for real-time device telemetry and event logs.",
    ).pack(fill=tk.X)
