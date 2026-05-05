import tkinter as tk


def section_card(parent: tk.Frame, palette: dict[str, str], title: str, body: str) -> tk.Frame:
    card = tk.Frame(parent, bg=palette["card"], bd=1, relief=tk.SOLID, highlightthickness=0)
    tk.Label(
        card,
        text=title,
        bg=palette["card"],
        fg=palette["text"],
        font=("Helvetica", 13, "bold"),
    ).pack(anchor=tk.W, padx=12, pady=(10, 4))
    tk.Label(
        card,
        text=body,
        bg=palette["card"],
        fg=palette["muted"],
        justify=tk.LEFT,
        font=("Helvetica", 11),
    ).pack(anchor=tk.W, padx=12, pady=(0, 10))
    return card
