import tkinter as tk

from guardian.views.common import section_card

TITLE = "HQ Overview"
SUBTITLE = "Monitor mission readiness, system health, and active operations."


def build(parent: tk.Frame, palette: dict[str, str]) -> None:
    grid = tk.Frame(parent, bg=palette["main"])
    grid.pack(fill=tk.BOTH, expand=True)
    grid.grid_columnconfigure(0, weight=1, uniform="cards")
    grid.grid_columnconfigure(1, weight=1, uniform="cards")
    grid.grid_rowconfigure(0, weight=1, uniform="cards")
    grid.grid_rowconfigure(1, weight=1, uniform="cards")

    items = [
        ("Mission Status", "No active mission. Last mission ended cleanly."),
        ("Device Fleet", "42 devices online, 3 pending calibration."),
        ("Alert Queue", "2 medium-priority alerts waiting for triage."),
        ("Operator Notes", "Use this panel for shift handover and reminders."),
    ]
    for idx, (title, body) in enumerate(items):
        row = idx // 2
        col = idx % 2
        section_card(grid, palette, title, body).grid(row=row, column=col, sticky="nsew", padx=6, pady=6)
