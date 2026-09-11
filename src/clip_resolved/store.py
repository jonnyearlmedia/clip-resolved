from __future__ import annotations

import json
import sqlite3
import time
from pathlib import Path
from typing import Iterable, Iterator

from .models import MediaAsset, VisualSample


SCHEMA = """
PRAGMA journal_mode=WAL;
PRAGMA foreign_keys=ON;

CREATE TABLE IF NOT EXISTS assets (
    id TEXT PRIMARY KEY,
    path TEXT NOT NULL UNIQUE,
    duration REAL NOT NULL,
    fps REAL NOT NULL,
    width INTEGER NOT NULL,
    height INTEGER NOT NULL,
    has_audio INTEGER NOT NULL,
    size INTEGER NOT NULL,
    mtime_ns INTEGER NOT NULL,
    indexed_at REAL
);

CREATE TABLE IF NOT EXISTS visual_samples (
    asset_id TEXT NOT NULL,
    time REAL NOT NULL,
    embedding_json TEXT NOT NULL,
    PRIMARY KEY (asset_id, time),
    FOREIGN KEY (asset_id) REFERENCES assets(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_visual_samples_asset ON visual_samples(asset_id);

CREATE TABLE IF NOT EXISTS transcripts (
    asset_id TEXT PRIMARY KEY,
    payload_json TEXT NOT NULL,
    indexed_at REAL NOT NULL,
    FOREIGN KEY (asset_id) REFERENCES assets(id) ON DELETE CASCADE
);
"""


class IndexStore:
    def __init__(self, db_path: str | Path) -> None:
        self.path = Path(db_path).expanduser().resolve()
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.conn = sqlite3.connect(self.path)
        self.conn.row_factory = sqlite3.Row
        self.conn.executescript(SCHEMA)

    @classmethod
    def for_project(cls, project_root: str | Path) -> "IndexStore":
        root = Path(project_root).expanduser().resolve()
        return cls(root / ".clip-resolved" / "index.sqlite3")

    def close(self) -> None:
        self.conn.close()

    def __enter__(self) -> "IndexStore":
        return self

    def __exit__(self, exc_type, exc, tb) -> None:
        self.close()

    def upsert_asset(self, asset: MediaAsset) -> None:
        # indexed_at is invalidated when the underlying source file changes.
        # Old visual rows can remain briefly; visual_index_is_current() will not
        # trust them and replace_visual_samples() deletes them atomically later.
        self.conn.execute(
            """
            INSERT INTO assets (
              id, path, duration, fps, width, height, has_audio, size, mtime_ns
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(path) DO UPDATE SET
              id=excluded.id,
              duration=excluded.duration,
              fps=excluded.fps,
              width=excluded.width,
              height=excluded.height,
              has_audio=excluded.has_audio,
              indexed_at=CASE
                WHEN assets.size != excluded.size OR assets.mtime_ns != excluded.mtime_ns
                THEN NULL
                ELSE assets.indexed_at
              END,
              size=excluded.size,
              mtime_ns=excluded.mtime_ns
            """,
            (
                asset.id,
                str(asset.path),
                asset.duration,
                asset.fps,
                asset.width,
                asset.height,
                int(asset.has_audio),
                asset.size,
                asset.mtime_ns,
            ),
        )
        self.conn.commit()

    def replace_visual_samples(self, asset_id: str, samples: Iterable[VisualSample]) -> None:
        rows = [
            (sample.asset_id, sample.time, json.dumps(sample.embedding, separators=(",", ":")))
            for sample in samples
        ]
        with self.conn:
            self.conn.execute("DELETE FROM visual_samples WHERE asset_id = ?", (asset_id,))
            self.conn.executemany(
                "INSERT INTO visual_samples (asset_id, time, embedding_json) VALUES (?, ?, ?)",
                rows,
            )
            self.conn.execute(
                "UPDATE assets SET indexed_at = ? WHERE id = ?",
                (time.time(), asset_id),
            )

    def visual_index_is_current(self, asset: MediaAsset) -> bool:
        row = self.conn.execute(
            "SELECT id, size, mtime_ns, indexed_at FROM assets WHERE path = ?",
            (str(asset.path),),
        ).fetchone()
        if not row or row["indexed_at"] is None:
            return False
        if int(row["size"]) != asset.size or int(row["mtime_ns"]) != asset.mtime_ns:
            return False
        count = self.conn.execute(
            "SELECT COUNT(*) AS n FROM visual_samples WHERE asset_id = ?",
            (row["id"],),
        ).fetchone()["n"]
        return int(count) > 0

    def iter_visual_samples(self) -> Iterator[tuple[MediaAsset, VisualSample]]:
        rows = self.conn.execute(
            """
            SELECT
              a.id, a.path, a.duration, a.fps, a.width, a.height, a.has_audio,
              a.size, a.mtime_ns,
              v.time, v.embedding_json
            FROM visual_samples v
            JOIN assets a ON a.id = v.asset_id
            ORDER BY a.path, v.time
            """
        )
        for row in rows:
            asset = MediaAsset(
                id=row["id"],
                path=Path(row["path"]),
                duration=float(row["duration"]),
                fps=float(row["fps"]),
                width=int(row["width"]),
                height=int(row["height"]),
                has_audio=bool(row["has_audio"]),
                size=int(row["size"]),
                mtime_ns=int(row["mtime_ns"]),
            )
            embedding = tuple(float(v) for v in json.loads(row["embedding_json"]))
            yield asset, VisualSample(asset_id=asset.id, time=float(row["time"]), embedding=embedding)

    def get_asset(self, asset_id: str) -> MediaAsset | None:
        row = self.conn.execute("SELECT * FROM assets WHERE id = ?", (asset_id,)).fetchone()
        if row is None:
            return None
        return MediaAsset(
            id=row["id"],
            path=Path(row["path"]),
            duration=float(row["duration"]),
            fps=float(row["fps"]),
            width=int(row["width"]),
            height=int(row["height"]),
            has_audio=bool(row["has_audio"]),
            size=int(row["size"]),
            mtime_ns=int(row["mtime_ns"]),
        )

    def asset_count(self) -> int:
        return int(self.conn.execute("SELECT COUNT(*) FROM assets").fetchone()[0])

    def visual_sample_count(self) -> int:
        return int(self.conn.execute("SELECT COUNT(*) FROM visual_samples").fetchone()[0])
