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
    capture_time REAL,
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
        columns = {
            row["name"] for row in self.conn.execute("PRAGMA table_info(assets)")
        }
        if "capture_time" not in columns:
            self.conn.execute("ALTER TABLE assets ADD COLUMN capture_time REAL")
            self.conn.commit()

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
        existing = self.conn.execute(
            "SELECT id, size, mtime_ns FROM assets WHERE path = ?", (str(asset.path),)
        ).fetchone()
        changed = bool(
            existing
            and (int(existing["size"]) != asset.size or int(existing["mtime_ns"]) != asset.mtime_ns)
        )
        self.conn.execute(
            """
            INSERT INTO assets (
              id, path, duration, fps, width, height, has_audio, size, mtime_ns, capture_time
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
              mtime_ns=excluded.mtime_ns,
              capture_time=excluded.capture_time
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
                asset.capture_time,
            ),
        )
        if changed and existing:
            self.conn.execute("DELETE FROM transcripts WHERE asset_id = ?", (existing["id"],))
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
              a.size, a.mtime_ns, a.capture_time,
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
                capture_time=float(row["capture_time"]) if row["capture_time"] is not None else None,
            )
            embedding = tuple(float(v) for v in json.loads(row["embedding_json"]))
            yield asset, VisualSample(asset_id=asset.id, time=float(row["time"]), embedding=embedding)

    def get_asset(self, asset_id: str) -> MediaAsset | None:
        row = self.conn.execute("SELECT * FROM assets WHERE id = ?", (asset_id,)).fetchone()
        if row is None:
            return None
        return self._asset_from_row(row)

    def get_asset_by_path(self, path: str | Path) -> MediaAsset | None:
        normalized = str(Path(path).expanduser().resolve())
        row = self.conn.execute("SELECT * FROM assets WHERE path = ?", (normalized,)).fetchone()
        return self._asset_from_row(row) if row is not None else None

    def visual_samples_for_asset(self, asset_id: str) -> list[VisualSample]:
        rows = self.conn.execute(
            "SELECT time, embedding_json FROM visual_samples WHERE asset_id = ? ORDER BY time",
            (asset_id,),
        )
        return [
            VisualSample(
                asset_id=asset_id,
                time=float(row["time"]),
                embedding=tuple(float(value) for value in json.loads(row["embedding_json"])),
            )
            for row in rows
        ]

    def delete_asset(self, asset_id: str) -> None:
        with self.conn:
            self.conn.execute("DELETE FROM assets WHERE id = ?", (asset_id,))

    def transfer_asset_to(
        self,
        destination_store: "IndexStore",
        source_path: str | Path,
        destination_path: str | Path,
    ) -> MediaAsset | None:
        """Move one indexed asset between projects without recomputing CLIP data.

        The media file must already exist at destination_path. The destination
        row and every visual/transcript child are committed before the source
        row is removed, so an interrupted correction never loses the index.
        """
        from .ffprobe import asset_id_for_path

        source = self.get_asset_by_path(source_path)
        if source is None:
            return None
        destination = Path(destination_path).expanduser().resolve()
        stat = destination.stat()
        if stat.st_size != source.size:
            raise ValueError(
                f"Moved file size changed for {destination.name}: expected {source.size}, got {stat.st_size}"
            )
        moved = MediaAsset(
            id=asset_id_for_path(destination),
            path=destination,
            duration=source.duration,
            fps=source.fps,
            width=source.width,
            height=source.height,
            has_audio=source.has_audio,
            size=stat.st_size,
            mtime_ns=stat.st_mtime_ns,
            capture_time=source.capture_time,
        )
        samples = [
            VisualSample(
                asset_id=moved.id,
                time=sample.time,
                embedding=sample.embedding,
            )
            for sample in self.visual_samples_for_asset(source.id)
        ]
        transcript = self.get_transcript(source.id)
        destination_store.upsert_asset(moved)
        if samples:
            destination_store.replace_visual_samples(moved.id, samples)
        if transcript is not None:
            destination_store.put_transcript(moved.id, transcript)
        self.delete_asset(source.id)
        return moved

    @staticmethod
    def _asset_from_row(row: sqlite3.Row) -> MediaAsset:
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
            capture_time=float(row["capture_time"]) if row["capture_time"] is not None else None,
        )

    def iter_assets(self) -> Iterator[MediaAsset]:
        rows = self.conn.execute("SELECT * FROM assets ORDER BY path")
        for row in rows:
            yield self._asset_from_row(row)

    def asset_count(self) -> int:
        return int(self.conn.execute("SELECT COUNT(*) FROM assets").fetchone()[0])

    def video_asset_count(self) -> int:
        return int(
            self.conn.execute(
                "SELECT COUNT(*) FROM assets WHERE width > 0 AND height > 0"
            ).fetchone()[0]
        )

    def visual_sample_count(self) -> int:
        return int(self.conn.execute("SELECT COUNT(*) FROM visual_samples").fetchone()[0])

    def put_transcript(self, asset_id: str, payload: dict) -> None:
        with self.conn:
            self.conn.execute(
                """
                INSERT INTO transcripts (asset_id, payload_json, indexed_at)
                VALUES (?, ?, ?)
                ON CONFLICT(asset_id) DO UPDATE SET
                  payload_json=excluded.payload_json,
                  indexed_at=excluded.indexed_at
                """,
                (asset_id, json.dumps(payload, separators=(",", ":")), time.time()),
            )

    def get_transcript(self, asset_id: str) -> dict | None:
        row = self.conn.execute(
            "SELECT payload_json FROM transcripts WHERE asset_id = ?", (asset_id,)
        ).fetchone()
        return json.loads(row["payload_json"]) if row else None

    def iter_transcripts(self) -> Iterator[tuple[MediaAsset, dict]]:
        rows = self.conn.execute(
            """
            SELECT a.*, t.payload_json
            FROM transcripts t
            JOIN assets a ON a.id = t.asset_id
            ORDER BY a.path
            """
        )
        for row in rows:
            yield self._asset_from_row(row), json.loads(row["payload_json"])

    def transcript_count(self) -> int:
        return int(self.conn.execute("SELECT COUNT(*) FROM transcripts").fetchone()[0])
