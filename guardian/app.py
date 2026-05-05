import tkinter as tk

from guardian.platform.integrations import detect_platform_info


class GuardianApp:
    def __init__(self) -> None:
        self.platform = detect_platform_info()
        self.root = tk.Tk()
        self.root.title("Guardian")
        self.current_view = "dashboard"
        self.palette = self._dark_palette()
        self._apply_global_palette()
        self.page_meta = {
            "dashboard": {"title": "Dashboard", "subtitle": "HQ mission and fleet overview."},
            "devices": {"title": "Devices", "subtitle": "Manage connected devices."},
            "missions": {"title": "Missions", "subtitle": "Create and manage mission plans."},
            "mission_control": {
                "title": "Mission Control",
                "subtitle": "Operate active missions in real time.",
            },
        }
        self.title_var = tk.StringVar(value=self.page_meta["dashboard"]["title"])
        self.subtitle_var = tk.StringVar(value=self.page_meta["dashboard"]["subtitle"])
        self.nav_buttons: dict[str, tk.Label] = {}
        self.page_frames: dict[str, tk.Frame] = {}
        self.nav_items = [
            ("dashboard", "Dashboard"),
            ("devices", "Devices"),
            ("missions", "Missions"),
            ("mission_control", "Mission Control"),
        ]
        self.root.after(10, self._lock_full_size)
        self._build_ui()
        self._switch_view("dashboard")

    def _build_ui(self) -> None:
        self.root.configure(bg=self.palette["main"])
        root_frame = tk.Frame(self.root, bg=self.palette["main"])
        root_frame.pack(fill=tk.BOTH, expand=True)

        sidebar = tk.Frame(
            root_frame,
            width=260,
            bg=self.palette["rail"],
            highlightbackground=self.palette["edge"],
            highlightthickness=1,
            bd=0,
        )
        sidebar.pack(side=tk.LEFT, fill=tk.Y)
        sidebar.pack_propagate(False)

        brand = tk.Label(
            sidebar,
            text="Guardian",
            bg=self.palette["rail"],
            fg=self.palette["text"],
            font=("Helvetica", 16, "bold"),
        )
        brand.pack(anchor=tk.W, padx=16, pady=(20, 12))

        for key, label in self.nav_items:
            button = tk.Label(
                sidebar,
                text=label,
                bg=self.palette["rail"],
                fg=self.palette["text"],
                anchor="w",
                padx=16,
                pady=8,
                cursor="hand2",
            )
            button.bind("<Button-1>", lambda _event, selected=key: self._switch_view(selected))
            button.pack(anchor=tk.W, fill=tk.X, pady=1)
            self.nav_buttons[key] = button

        content = tk.Frame(root_frame, bg=self.palette["main"])
        content.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)

        top_bar = tk.Frame(
            content,
            bg=self.palette["bar"],
            height=52,
            highlightbackground=self.palette["edge"],
            highlightthickness=1,
            bd=0,
        )
        top_bar.pack(fill=tk.X)
        top_bar.pack_propagate(False)
        tk.Label(
            top_bar,
            text="Guardian HQ",
            bg=self.palette["bar"],
            fg=self.palette["text"],
            font=("Helvetica", 13, "bold"),
        ).pack(side=tk.LEFT, padx=16)
        tk.Label(
            top_bar,
            text="Dark Mode",
            bg=self.palette["bar"],
            fg=self.palette["muted"],
            font=("Helvetica", 10, "bold"),
        ).pack(side=tk.RIGHT, padx=16)

        header = tk.Frame(content, bg=self.palette["main"])
        header.pack(fill=tk.X, padx=20, pady=(16, 8))
        tk.Label(
            header,
            textvariable=self.title_var,
            bg=self.palette["main"],
            fg=self.palette["text"],
            font=("Helvetica", 24, "bold"),
        ).pack(anchor=tk.W)
        tk.Label(
            header,
            textvariable=self.subtitle_var,
            bg=self.palette["main"],
            fg=self.palette["muted"],
            font=("Helvetica", 12),
        ).pack(anchor=tk.W, pady=(2, 12))

        toolbar = tk.Frame(content, bg=self.palette["main"])
        toolbar.pack(fill=tk.X, padx=20, pady=(0, 10))
        tk.Button(
            toolbar,
            text="Add Device",
            padx=10,
            bg=self.palette["card"],
            fg=self.palette["text"],
            activebackground=self.palette["nav_active"],
            activeforeground=self.palette["text"],
            relief=tk.FLAT,
            bd=0,
        ).pack(side=tk.LEFT)
        tk.Button(
            toolbar,
            text="Create Mission",
            padx=10,
            bg=self.palette["card"],
            fg=self.palette["text"],
            activebackground=self.palette["nav_active"],
            activeforeground=self.palette["text"],
            relief=tk.FLAT,
            bd=0,
        ).pack(side=tk.LEFT, padx=8)
        tk.Button(
            toolbar,
            text="Start Live Control",
            padx=10,
            bg=self.palette["card"],
            fg=self.palette["text"],
            activebackground=self.palette["nav_active"],
            activeforeground=self.palette["text"],
            relief=tk.FLAT,
            bd=0,
        ).pack(side=tk.LEFT)

        self.view_container = tk.Frame(content, bg=self.palette["main"])
        self.view_container.pack(fill=tk.BOTH, expand=True, padx=20, pady=(0, 20))
        self.view_container.grid_rowconfigure(0, weight=1)
        self.view_container.grid_columnconfigure(0, weight=1)
        self._build_page_frames()

    def _switch_view(self, page_key: str) -> None:
        self.current_view = page_key
        for key, button in self.nav_buttons.items():
            if key == page_key:
                button.configure(
                    bg=self.palette["nav_active"],
                    fg=self.palette["text"],
                    font=("Helvetica", 12, "bold"),
                )
            else:
                button.configure(
                    bg=self.palette["rail"],
                    fg=self.palette["text"],
                    font=("Helvetica", 12),
                )
        self._set_header_for_view(page_key)
        self._show_page(page_key)

    def _set_header_for_view(self, page_key: str) -> None:
        self.title_var.set(self.page_meta[page_key]["title"])
        self.subtitle_var.set(self.page_meta[page_key]["subtitle"])

    def _build_page_frames(self) -> None:
        self.page_frames = {}
        for key, meta in self.page_meta.items():
            frame = tk.Frame(self.view_container, bg=self.palette["main"])
            frame.grid(row=0, column=0, sticky="nsew")
            tk.Label(
                frame,
                text=meta["title"],
                bg=self.palette["main"],
                fg=self.palette["text"],
                font=("Helvetica", 34, "bold"),
            ).pack(anchor=tk.CENTER, expand=True)
            self.page_frames[key] = frame

    def _show_page(self, page_key: str) -> None:
        frame = self.page_frames[page_key]
        frame.tkraise()

    def _dark_palette(self) -> dict[str, str]:
        return {
            "main": "#121212",
            "rail": "#1c1c1c",
            "bar": "#202020",
            "card": "#2a2a2a",
            "text": "#ffffff",
            "muted": "#b3b3b3",
            "nav_active": "#303030",
            "edge": "#3e3e3e",
        }

    def _apply_global_palette(self) -> None:
        self.root.configure(bg=self.palette["main"])
        self.root.tk_setPalette(
            background=self.palette["main"],
            foreground=self.palette["text"],
            activeBackground=self.palette["nav_active"],
            activeForeground=self.palette["text"],
            highlightColor=self.palette["edge"],
        )
        self.root.option_add("*Background", self.palette["main"])
        self.root.option_add("*Frame.Background", self.palette["main"])
        self.root.option_add("*Label.Background", self.palette["main"])
        self.root.option_add("*Label.Foreground", self.palette["text"])
        self.root.option_add("*Button.Background", self.palette["card"])
        self.root.option_add("*Button.Foreground", self.palette["text"])

    def _lock_full_size(self) -> None:
        width = self.root.winfo_screenwidth()
        height = self.root.winfo_screenheight()
        self.root.geometry(f"{width}x{height}+0+0")
        self.root.minsize(width, height)
        self.root.maxsize(width, height)

    def run(self) -> None:
        self.root.mainloop()
