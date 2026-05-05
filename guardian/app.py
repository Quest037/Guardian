import tkinter as tk
from tkinter import ttk

from guardian.platform.integrations import detect_platform_info


class GuardianApp:
    def __init__(self) -> None:
        self.platform = detect_platform_info()
        self.root = tk.Tk()
        self.root.title("Guardian")
        self.root.geometry("520x280")
        self.root.minsize(420, 220)
        self._build_ui()

    def _build_ui(self) -> None:
        container = ttk.Frame(self.root, padding=20)
        container.pack(fill=tk.BOTH, expand=True)

        title = ttk.Label(container, text="Guardian", font=("Helvetica", 22, "bold"))
        title.pack(anchor=tk.W)

        subtitle = ttk.Label(
            container,
            text="Mac-first desktop app with cross-OS architecture",
            font=("Helvetica", 11),
        )
        subtitle.pack(anchor=tk.W, pady=(4, 16))

        details = [
            f"Detected OS: {self.platform.os_name}",
            f"OS Version: {self.platform.os_version}",
            f"Supported Platform: {'Yes' if self.platform.is_supported else 'No'}",
            f"Notifications: {'Yes' if self.platform.supports_notifications else 'No'}",
            f"Global Shortcuts: {'Yes' if self.platform.supports_global_shortcuts else 'No'}",
        ]

        for line in details:
            ttk.Label(container, text=line).pack(anchor=tk.W, pady=1)

    def run(self) -> None:
        self.root.mainloop()
