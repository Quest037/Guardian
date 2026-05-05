# Guardian

Guardian is a desktop app foundation built for macOS first, with a cross-OS architecture from day one.

## Why this stack

- **Mac-first**: clean native-feeling desktop UI with `tkinter` for quick iteration on macOS.
- **Cross-OS ready**: runtime and platform adapters are structured to support Linux and Windows without a rewrite.
- **Low friction**: zero third-party dependencies for initial development.

## Project layout

- `main.py`: application entry point.
- `guardian/app.py`: UI app shell.
- `guardian/platform/integrations.py`: OS capability detection and adapter surface.
- `tests/`: basic test coverage.

## Run locally

```bash
python3 main.py
```

## Run tests

```bash
python3 -m unittest discover -s tests -p "test_*.py"
```

## Cross-OS plan

The `platform` module is the compatibility seam. As Guardian evolves:

1. Keep core features OS-agnostic in shared modules.
2. Add platform adapters per OS in `guardian/platform/`.
3. Gate platform-specific behavior with explicit capability checks.
