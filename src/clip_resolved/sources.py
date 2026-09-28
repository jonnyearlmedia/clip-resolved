from __future__ import annotations

import json
import re
from dataclasses import asdict, dataclass
from pathlib import Path


@dataclass(frozen=True)
class ProjectSource:
    label: str
    path: str
    kind: str = "camera"

    @property
    def root(self) -> Path:
        return Path(self.path).expanduser().resolve()


def _manifest_path(project_root: str | Path) -> Path:
    root = Path(project_root).expanduser().resolve()
    return root / ".clip-resolved" / "sources.json"


def normalize_source_label(label: str) -> str:
    value = re.sub(r"[^A-Za-z0-9 +&_-]+", " ", label).strip()
    value = re.sub(r"\s+", " ", value).upper()
    return value[:48] or "CAMERA"


def infer_source_label(source: str | Path) -> str:
    root = Path(source).expanduser().resolve()
    haystack = str(root).lower()
    names: list[str] = []
    if root.is_file():
        names = [root.name.lower()]
    elif root.exists():
        names = [item.name.lower() for item in list(root.rglob("*"))[:200] if item.is_file()]
    joined = " ".join(names)
    if "insta360" in haystack or "go ultra" in haystack or any("insv" in name for name in names):
        return "INSTA360 GO ULTRA"
    if "iphone" in haystack or "100apple" in haystack or any(re.match(r"img_\d+\.(mov|mp4)$", name) for name in names):
        return "IPHONE"
    if "osmo" in haystack or any(re.match(r"dji_.*\.(mp4|mov)$", name) for name in names):
        return "OSMO"
    if not joined and root.suffix.lower() in {".wav", ".m4a", ".mp3", ".aif", ".aiff"}:
        return "EXTERNAL AUDIO"
    return normalize_source_label(root.stem if root.is_file() else root.name)


def load_sources(project_root: str | Path) -> list[ProjectSource]:
    path = _manifest_path(project_root)
    if not path.exists():
        return []
    payload = json.loads(path.read_text())
    result: list[ProjectSource] = []
    for item in payload.get("sources", []):
        source = ProjectSource(
            label=normalize_source_label(str(item.get("label") or "CAMERA")),
            path=str(Path(item["path"]).expanduser().resolve()),
            kind=str(item.get("kind") or "camera"),
        )
        if source.kind not in {"camera", "audio"}:
            continue
        result.append(source)
    return result


def register_source(
    project_root: str | Path,
    source: str | Path,
    *,
    label: str | None = None,
    kind: str = "camera",
) -> ProjectSource:
    if kind not in {"camera", "audio"}:
        raise ValueError("Source kind must be camera or audio")
    root = Path(source).expanduser().resolve()
    if not root.exists():
        raise ValueError(f"Source does not exist: {root}")
    record = ProjectSource(
        label=normalize_source_label(label or infer_source_label(root)),
        path=str(root),
        kind=kind,
    )
    sources = load_sources(project_root)
    normalized_path = str(root)
    replacement_index = next(
        (index for index, item in enumerate(sources) if item.path == normalized_path),
        None,
    )
    if replacement_index is None:
        sources.append(record)
    else:
        sources[replacement_index] = record

    manifest = _manifest_path(project_root)
    manifest.parent.mkdir(parents=True, exist_ok=True)
    payload = {"schema": 1, "sources": [asdict(item) for item in sources]}
    temporary = manifest.with_suffix(".json.tmp")
    temporary.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
    temporary.replace(manifest)
    return record


def source_for_path(project_root: str | Path, path: str | Path) -> ProjectSource | None:
    candidate = Path(path).expanduser().resolve()
    matches: list[tuple[int, ProjectSource]] = []
    for source in load_sources(project_root):
        try:
            candidate.relative_to(source.root if source.root.is_dir() else source.root.parent)
        except ValueError:
            continue
        matches.append((len(source.root.parts), source))
    return max(matches, default=(0, None), key=lambda item: item[0])[1]
