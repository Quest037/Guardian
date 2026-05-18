# Stack wiki (local PX4 & ArduPilot docs)

**Dev-only** documentation index for Cursor agents and contributors. Lives under repo-root `Resources/StackWiki/` — **not** in `Sources/GuardianHQ/Resources/` and **not** bundled into the GuardianHQ app.

## Search

After `make stack-wiki-refresh`, search the committed index:

```bash
grep -i offboard Resources/StackWiki/index/chunks.jsonl
# or open a chunk and read the JSON "text" field
```

Each line is one JSON chunk with `project`, `title`, `heading_path`, `url`, `license`, `retrieved_at`, and `text`.

## Refresh

```bash
make stack-wiki-deps    # once: docutils for RST → text
make stack-wiki-refresh # fetch upstream + rebuild index + manifest
```

**Disk (approx.):** sparse PX4 `docs/` clone ~tens of MB; full `ardupilot_wiki` ~hundreds of MB under `upstream/` (gitignored). Index ~20 MB `chunks.jsonl` (tracked); `chunks.jsonl.gz` is local-only (~4 MB).

**Cadence:** ArduPilot’s public wiki rebuilds about daily; parameter tables every 2–3 days. Refresh weekly or before stack-heavy work. See `manifest.json` → `retrieved_at`.

## Layout

| Path | In git | Purpose |
|------|--------|---------|
| `manifest.json` | yes | Pinned commits, chunk counts, content hash |
| `index/chunks.jsonl` | yes | Heading-sized chunks for grep / read |
| `upstream/` | no | `PX4-Autopilot`, `ardupilot_wiki` clones |
| `source/` | no | Optional normalized text mirror (debug) |

## Canonical URLs

| Source | Example repo path | Published URL |
|--------|-------------------|---------------|
| PX4 | `docs/en/flight_modes/offboard.md` | `https://docs.px4.io/main/en/flight_modes/offboard.html` |
| ArduPilot | `rover/source/docs/rover-steering-mode.rst` | `https://ardupilot.org/rover/docs/rover-steering-mode.html` |
| ArduPilot common | `common/source/docs/common-offboard-guiding.rst` | `https://ardupilot.org/copter/docs/common-offboard-guiding.html` |

## Licenses (cite when quoting)

- **PX4 User Guide:** [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/)
- **ArduPilot Wiki:** [CC BY-SA 3.0](https://creativecommons.org/licenses/by-sa/3.0/)

Example citation footer: `Source: PX4 User Guide, CC BY 4.0, retrieved 2026-05-18`

## Agent policy

`.cursor/rules/stack-wiki-docs-local.mdc` — local index first, then Guardian docs, then web only when missing or stale (&gt;14 days on parameter/mode-sensitive topics).
