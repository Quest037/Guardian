#!/usr/bin/env python3
"""
Extract PX4 + ArduPilot wiki sources from Resources/StackWiki/upstream/ and write
Resources/StackWiki/index/chunks.jsonl (+ .gz) and manifest.json.
"""

from __future__ import annotations

import gzip
import hashlib
import json
import re
import shutil
import subprocess
import sys
from dataclasses import dataclass
from datetime import date
from pathlib import Path
from typing import Iterator

ROOT = Path(__file__).resolve().parents[2]
STACK_WIKI = ROOT / "Resources" / "StackWiki"
UPSTREAM = STACK_WIKI / "upstream"
PX4_ROOT = UPSTREAM / "PX4-Autopilot"
AP_WIKI = UPSTREAM / "ardupilot_wiki"
SOURCE_MIRROR = STACK_WIKI / "source"
INDEX_DIR = STACK_WIKI / "index"
CHUNKS_PATH = INDEX_DIR / "chunks.jsonl"
CHUNKS_GZ_PATH = INDEX_DIR / "chunks.jsonl.gz"
MANIFEST_PATH = STACK_WIKI / "manifest.json"

MAX_CHUNK_CHARS = 12_000
MIN_CHUNK_CHARS = 120

PX4_LICENSE = "CC BY 4.0"
AP_LICENSE = "CC BY-SA 3.0"

AP_SITE_VEHICLES = frozenset(
    {"copter", "plane", "rover", "blimp", "sub", "dev", "ardupilot", "planner", "planner2", "mavproxy"}
)

SKIP_DIR_NAMES = frozenset(
    {
        "_book",
        "_build",
        "_static",
        "_templates",
        ".git",
        "__pycache__",
        "images",
        "locale",
        "assets",
    }
)

NOISE_PATTERNS = [
    re.compile(r"^Edit on GitHub.*$", re.MULTILINE | re.IGNORECASE),
    re.compile(r"^```{eval-rst}.*?^```\s*$", re.MULTILINE | re.DOTALL),
    re.compile(r"^:::\s*\w+.*?^:::\s*$", re.MULTILINE | re.DOTALL),
    re.compile(r"<!--.*?-->", re.DOTALL),
    re.compile(r"\[menu\].*?\[/menu\]", re.DOTALL | re.IGNORECASE),
]


@dataclass(frozen=True)
class DocSource:
    project: str
    license: str
    doc_version: str
    commit: str
    source_path: str  # repo-relative
    url: str
    raw_text: str


def git_head(repo: Path) -> str:
    out = subprocess.check_output(["git", "-C", str(repo), "rev-parse", "HEAD"], text=True)
    return out.strip()


def strip_noise(text: str) -> str:
    t = text.replace("\r\n", "\n")
    for pat in NOISE_PATTERNS:
        t = pat.sub("", t)
    # Drop repeated nav-style bullet-only lines at top (PX4 book menus).
    lines = t.split("\n")
    cleaned: list[str] = []
    skipped_nav = True
    for line in lines:
        if skipped_nav and re.match(r"^[\s\-\*\>]*$", line):
            continue
        if skipped_nav and line.strip().startswith(("- ", "* ", "> ")) and len(line) < 120:
            continue
        skipped_nav = False
        cleaned.append(line)
    t = "\n".join(cleaned)
    t = re.sub(r"\n{3,}", "\n\n", t).strip()
    return t


def rst_to_text(body: str) -> str:
    try:
        from docutils.core import publish_string
        from docutils.writers._html_base import Writer  # noqa: F401 — ensure docutils present

        html = publish_string(
            source=body,
            writer_name="html",
            settings_overrides={
                "report_level": 5,
                "halt_level": 5,
                "input_encoding": "utf-8",
                "output_encoding": "utf-8",
            },
        ).decode("utf-8", errors="replace")
    except Exception:
        return _rst_fallback(body)

    text = re.sub(r"<(script|style)[^>]*>.*?</\1>", "", html, flags=re.DOTALL | re.IGNORECASE)
    text = re.sub(r"<br\s*/?>", "\n", text, flags=re.IGNORECASE)
    text = re.sub(r"</(p|div|h[1-6]|li|tr)>", "\n", text, flags=re.IGNORECASE)
    text = re.sub(r"<[^>]+>", "", text)
    text = re.sub(r"&nbsp;", " ", text)
    text = re.sub(r"&amp;", "&", text)
    text = re.sub(r"&lt;", "<", text)
    text = re.sub(r"&gt;", ">", text)
    text = re.sub(r"\n{3,}", "\n\n", text)
    return strip_noise(text.strip())


def _rst_fallback(body: str) -> str:
    lines: list[str] = []
    skip = False
    for line in body.splitlines():
        if line.strip().startswith(".. ") and "::" in line:
            skip = True
            continue
        if skip and line and not line[0].isspace():
            skip = False
        if skip:
            continue
        if line.strip().startswith(".. "):
            continue
        lines.append(line)
    return strip_noise("\n".join(lines))


def md_to_text(body: str) -> str:
    return strip_noise(body)


def px4_canonical_url(rel_from_en: str) -> str:
    path = rel_from_en.replace("\\", "/")
    if path.endswith(".md"):
        path = path[: -len(".md")] + ".html"
    return f"https://docs.px4.io/main/en/{path}"


def ardupilot_canonical_url(rel_path: str) -> str:
    """Map wiki repo path to ardupilot.org HTML URL."""
    p = rel_path.replace("\\", "/")
    # e.g. rover/source/docs/foo.rst, common/source/docs/common-bar.rst
    parts = p.split("/")
    vehicle = parts[0] if parts else "copter"
    if vehicle == "common":
        site_vehicle = "copter"
    elif vehicle in AP_SITE_VEHICLES:
        site_vehicle = vehicle
    else:
        site_vehicle = "copter"
    name = Path(p).stem
    return f"https://ardupilot.org/{site_vehicle}/docs/{name}.html"


def should_skip_path(path: Path) -> bool:
    return any(part in SKIP_DIR_NAMES for part in path.parts)


def iter_px4_docs() -> Iterator[DocSource]:
    docs_en = PX4_ROOT / "docs" / "en"
    if not docs_en.is_dir():
        raise SystemExit(f"Missing PX4 docs: {docs_en} — run fetch_upstream.sh first")
    commit = git_head(PX4_ROOT)
    ref = "main"
    for path in sorted(docs_en.rglob("*.md")):
        if should_skip_path(path.relative_to(PX4_ROOT)):
            continue
        rel_en = path.relative_to(docs_en).as_posix()
        rel_repo = f"docs/en/{rel_en}"
        body = path.read_text(encoding="utf-8", errors="replace")
        yield DocSource(
            project="PX4",
            license=PX4_LICENSE,
            doc_version=ref,
            commit=commit,
            source_path=rel_repo,
            url=px4_canonical_url(rel_en),
            raw_text=md_to_text(body),
        )


def iter_ardupilot_docs() -> Iterator[DocSource]:
    if not AP_WIKI.is_dir():
        raise SystemExit(f"Missing ArduPilot wiki: {AP_WIKI} — run fetch_upstream.sh first")
    commit = git_head(AP_WIKI)
    ref = "master"
    patterns = ("*.rst", "*.md")
    for pattern in patterns:
        for path in sorted(AP_WIKI.rglob(pattern)):
            rel = path.relative_to(AP_WIKI)
            if should_skip_path(rel):
                continue
            top = rel.parts[0] if rel.parts else ""
            if top not in AP_SITE_VEHICLES and top != "common":
                continue
            if "/source/docs/" not in rel.as_posix():
                continue
            body = path.read_text(encoding="utf-8", errors="replace")
            if path.suffix.lower() == ".rst":
                text = rst_to_text(body)
            else:
                text = md_to_text(body)
            yield DocSource(
                project="ArduPilot",
                license=AP_LICENSE,
                doc_version=f"wiki/{ref}",
                commit=commit,
                source_path=rel.as_posix(),
                url=ardupilot_canonical_url(rel.as_posix()),
                raw_text=text,
            )


def parse_heading_level(line: str) -> int | None:
    m = re.match(r"^(#{1,6})\s+(.+)$", line.strip())
    if m:
        return len(m.group(1)), m.group(2).strip()
    m = re.match(r"^([=\-`:\.'\"~^_*+#]{3,})\s*$", line)
    if m:
        return None  # RST underline — handled separately
    m = re.match(r"^(.+)\n[=\-]{3,}\s*$", line)
    return None


def split_sections(text: str, doc_title: str) -> list[tuple[list[str], str]]:
    """Return (heading_path, section_body) including title-derived root."""
    lines = text.split("\n")
    sections: list[tuple[list[str], list[str]]] = []
    heading_path: list[str] = [doc_title] if doc_title else []
    current: list[str] = []

    def flush() -> None:
        body = "\n".join(current).strip()
        if body:
            sections.append((heading_path.copy(), body))
        current.clear()

    i = 0
    while i < len(lines):
        line = lines[i]
        md = re.match(r"^(#{1,6})\s+(.+)$", line)
        if md:
            flush()
            level = len(md.group(1))
            title = clean_heading_title(md.group(2).strip())
            heading_path = heading_path[: level - 1] + [title]
            i += 1
            continue
        # RST-style title + underline
        if i + 1 < len(lines):
            ul = lines[i + 1].strip()
            if line.strip() and re.match(r"^[=\-~^\"']{3,}$", ul):
                flush()
                title = clean_heading_title(line.strip())
                level = 1 if ul[0] == "=" else 2
                heading_path = heading_path[: level - 1] + [title]
                i += 2
                continue
        current.append(line)
        i += 1
    flush()
    if not sections and text.strip():
        sections.append((heading_path or [doc_title or "Document"], text.strip()))
    return sections


def clean_heading_title(title: str) -> str:
    return re.sub(r"\s*\{#[^}]+\}\s*", "", title).strip()


def doc_title_from_path(source_path: str) -> str:
    stem = Path(source_path).stem
    stem = re.sub(r"^common-", "", stem)
    stem = re.sub(r"[-_]+", " ", stem)
    return stem.strip().title() or "Document"


def split_oversized(body: str, heading_path: list[str]) -> list[tuple[list[str], str]]:
    if len(body) <= MAX_CHUNK_CHARS:
        return [(heading_path, body)]
    parts: list[tuple[list[str], str]] = []
    paras = re.split(r"\n\n+", body)
    buf: list[str] = []
    buf_len = 0
    part_idx = 0

    def emit_buf() -> None:
        nonlocal buf, buf_len, part_idx
        if not buf:
            return
        part_path = heading_path + ([f"part {part_idx + 1}"] if part_idx else [])
        parts.append((part_path, "\n\n".join(buf).strip()))
        part_idx += 1
        buf = []
        buf_len = 0

    for para in paras:
        plen = len(para) + 2
        if buf_len + plen > MAX_CHUNK_CHARS and buf:
            emit_buf()
        if len(para) > MAX_CHUNK_CHARS:
            emit_buf()
            for start in range(0, len(para), MAX_CHUNK_CHARS):
                chunk = para[start : start + MAX_CHUNK_CHARS]
                part_path = heading_path + [f"part {part_idx + 1}"]
                parts.append((part_path, chunk))
                part_idx += 1
            continue
        buf.append(para)
        buf_len += plen
    emit_buf()
    return parts


def chunk_document(doc: DocSource, retrieved_at: str) -> list[dict]:
    title = doc_title_from_path(doc.source_path)
    sections = split_sections(doc.raw_text, title)
    chunks: list[dict] = []
    pending_small: dict | None = None

    for heading_path, body in sections:
        for hpath, part in split_oversized(body, heading_path):
            if len(part) < MIN_CHUNK_CHARS:
                if pending_small is not None:
                    merged = pending_small["text"] + "\n\n" + part
                    if len(merged) <= MAX_CHUNK_CHARS:
                        pending_small["text"] = merged
                        pending_small["content_hash"] = hashlib.sha256(merged.encode()).hexdigest()
                        continue
                    chunks.append(pending_small)
                    pending_small = None
                if pending_small is None:
                    section_title = hpath[-1] if hpath else title
                    pending_small = _make_chunk(doc, retrieved_at, section_title, hpath, part)
                continue
            if pending_small is not None:
                chunks.append(pending_small)
                pending_small = None
            section_title = hpath[-1] if hpath else title
            chunks.append(_make_chunk(doc, retrieved_at, section_title, hpath, part))
    if pending_small is not None:
        chunks.append(pending_small)
    return chunks


def _make_chunk(
    doc: DocSource,
    retrieved_at: str,
    title: str,
    heading_path: list[str],
    text: str,
) -> dict:
    return {
        "project": doc.project,
        "doc_version": doc.doc_version,
        "commit": doc.commit,
        "title": title,
        "heading_path": heading_path,
        "source_path": doc.source_path,
        "url": doc.url,
        "license": doc.license,
        "retrieved_at": retrieved_at,
        "content_hash": hashlib.sha256(text.encode("utf-8")).hexdigest(),
        "text": text,
    }


def write_chunks(chunks: list[dict]) -> str:
    INDEX_DIR.mkdir(parents=True, exist_ok=True)
    with CHUNKS_PATH.open("w", encoding="utf-8") as f:
        for ch in chunks:
            f.write(json.dumps(ch, ensure_ascii=False) + "\n")
    content_hash = hashlib.sha256(CHUNKS_PATH.read_bytes()).hexdigest()
    with CHUNKS_PATH.open("rb") as src, gzip.open(CHUNKS_GZ_PATH, "wb", compresslevel=9) as gz:
        shutil.copyfileobj(src, gz)
    return content_hash


def write_manifest(
    *,
    retrieved_at: str,
    content_hash: str,
    chunks: list[dict],
    px4_commit: str,
    ap_commit: str,
) -> None:
    px4_count = sum(1 for c in chunks if c["project"] == "PX4")
    ap_count = sum(1 for c in chunks if c["project"] == "ArduPilot")
    manifest = {
        "retrieved_at": retrieved_at,
        "chunks_file": "index/chunks.jsonl",
        "chunks_gzip_local": "index/chunks.jsonl.gz",
        "content_hash": content_hash,
        "chunk_count": len(chunks),
        "px4": {
            "repo": "https://github.com/PX4/PX4-Autopilot.git",
            "ref": "main",
            "commit": px4_commit,
            "doc_version": "main",
            "license": PX4_LICENSE,
            "chunk_count": px4_count,
        },
        "ardupilot": {
            "repo": "https://github.com/ArduPilot/ardupilot_wiki.git",
            "ref": "master",
            "commit": ap_commit,
            "doc_version": "wiki/master",
            "license": AP_LICENSE,
            "chunk_count": ap_count,
        },
    }
    MANIFEST_PATH.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")


def mirror_sources(docs: list[DocSource]) -> None:
    if shutil.which("true") is None:
        return
    if SOURCE_MIRROR.exists():
        shutil.rmtree(SOURCE_MIRROR)
    for doc in docs:
        out = SOURCE_MIRROR / doc.project / doc.source_path
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(doc.raw_text, encoding="utf-8")


def main() -> int:
    retrieved_at = date.today().isoformat()
    all_chunks: list[dict] = []
    px4_docs = list(iter_px4_docs())
    ap_docs = list(iter_ardupilot_docs())
    print(f"PX4 pages: {len(px4_docs)}")
    print(f"ArduPilot pages: {len(ap_docs)}")
    for doc in px4_docs + ap_docs:
        all_chunks.extend(chunk_document(doc, retrieved_at))
    print(f"Chunks: {len(all_chunks)}")
    content_hash = write_chunks(all_chunks)
    px4_commit = git_head(PX4_ROOT)
    ap_commit = git_head(AP_WIKI)
    write_manifest(
        retrieved_at=retrieved_at,
        content_hash=content_hash,
        chunks=all_chunks,
        px4_commit=px4_commit,
        ap_commit=ap_commit,
    )
    size_mb = CHUNKS_PATH.stat().st_size / (1024 * 1024)
    gz_mb = CHUNKS_GZ_PATH.stat().st_size / (1024 * 1024)
    print(f"Wrote {CHUNKS_PATH} ({size_mb:.1f} MB), {CHUNKS_GZ_PATH} ({gz_mb:.1f} MB)")
    print(f"manifest content_hash={content_hash}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
