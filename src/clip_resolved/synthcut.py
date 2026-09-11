from __future__ import annotations

import json
import os
import subprocess
from pathlib import Path
from typing import Any


class SynthCutBridgeError(RuntimeError):
    pass


class SynthCutClipBridge:
    """Thin JSON-lines adapter around SynthCut's actual clip.ts implementation."""

    def __init__(self, repo_root: Path | None = None) -> None:
        self.repo_root = repo_root or Path(__file__).resolve().parents[2]
        self.synthcut_root = self.repo_root / "external" / "SynthCut"
        self.bridge_path = self.repo_root / "bridges" / "synthcut_clip_bridge.ts"
        self.tsx = self.synthcut_root / "node_modules" / ".bin" / "tsx"
        self._proc: subprocess.Popen[str] | None = None
        self._next_id = 1

    def start(self) -> None:
        if self._proc is not None and self._proc.poll() is None:
            return
        if not self.synthcut_root.exists():
            raise SynthCutBridgeError(
                f"SynthCut checkout missing at {self.synthcut_root}. "
                "Run scripts/bootstrap_upstreams.sh first."
            )
        if not self.tsx.exists():
            raise SynthCutBridgeError(
                f"SynthCut dependencies missing at {self.tsx}. "
                "Run scripts/bootstrap_upstreams.sh first."
            )
        env = os.environ.copy()
        env["CLIP_RESOLVED_SYNTHCUT_ROOT"] = str(self.synthcut_root)
        self._proc = subprocess.Popen(
            [str(self.tsx), str(self.bridge_path)],
            cwd=self.repo_root,
            env=env,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            text=True,
            bufsize=1,
        )

    def close(self) -> None:
        if self._proc is None:
            return
        if self._proc.stdin:
            self._proc.stdin.close()
        try:
            self._proc.wait(timeout=3)
        except subprocess.TimeoutExpired:
            self._proc.terminate()
        self._proc = None

    def __enter__(self) -> "SynthCutClipBridge":
        self.start()
        return self

    def __exit__(self, exc_type, exc, tb) -> None:
        self.close()

    def _request(self, op: str, **payload: Any) -> dict[str, Any]:
        self.start()
        assert self._proc is not None
        assert self._proc.stdin is not None
        assert self._proc.stdout is not None
        request_id = self._next_id
        self._next_id += 1
        request = {"id": request_id, "op": op, **payload}
        self._proc.stdin.write(json.dumps(request) + "\n")
        self._proc.stdin.flush()
        line = self._proc.stdout.readline()
        if not line:
            code = self._proc.poll()
            raise SynthCutBridgeError(f"SynthCut bridge exited unexpectedly (code={code})")
        response = json.loads(line)
        if response.get("id") != request_id:
            raise SynthCutBridgeError(
                f"SynthCut bridge response id mismatch: wanted {request_id}, got {response.get('id')}"
            )
        if not response.get("ok"):
            raise SynthCutBridgeError(response.get("error") or "SynthCut bridge request failed")
        return response

    def ensure_available(self) -> bool:
        return bool(self._request("ensure").get("available"))

    def embed_image(self, path: str | Path, time: float) -> tuple[float, ...] | None:
        response = self._request("embed_image", path=str(Path(path).resolve()), time=float(time))
        embedding = response.get("embedding")
        if embedding is None:
            return None
        return tuple(float(v) for v in embedding)

    def embed_text(self, query: str) -> tuple[float, ...] | None:
        response = self._request("embed_text", query=query)
        embedding = response.get("embedding")
        if embedding is None:
            return None
        return tuple(float(v) for v in embedding)
