#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXTERNAL="$ROOT/external"
mkdir -p "$EXTERNAL"

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing required command: $1" >&2
    exit 1
  }
}

need git
need python3
need node
need npm
need ffmpeg
need ffprobe

node -e 'const [a,b,c]=process.versions.node.split(".").map(Number); if (a<22 || (a===22 && b<12)) { console.error("SynthCut requires Node >= 22.12.0; found "+process.versions.node); process.exit(1) }'

clone_pin() {
  local name="$1"
  local repo="$2"
  local sha="$3"
  local dir="$4"

  echo "==> $name @ $sha"
  if [[ ! -d "$dir/.git" ]]; then
    git clone --filter=blob:none --no-checkout "$repo" "$dir"
  fi

  git -C "$dir" fetch --depth=1 origin "$sha"
  git -C "$dir" checkout --detach --force "$sha"
  git -C "$dir" clean -fdx
}

clone_pin \
  "SynthCut" \
  "https://github.com/Relo-video/SynthCut.git" \
  "96b1ca0e8b9935cc0d9561a3bc020f29bf9e88a0" \
  "$EXTERNAL/SynthCut"

clone_pin \
  "VideoHighlighter" \
  "https://github.com/Aseiel/VideoHighlighter.git" \
  "063e16416531679b98e39c7729c219e7ada362d9" \
  "$EXTERNAL/VideoHighlighter"

clone_pin \
  "davinci-resolve-mcp" \
  "https://github.com/samuelgursky/davinci-resolve-mcp.git" \
  "f4cd0f90d11431278ef5a24474ddad9d4e483251" \
  "$EXTERNAL/davinci-resolve-mcp"

clone_pin \
  "kontentmanager" \
  "https://github.com/SoCloseSociety/kontentmanager.git" \
  "900194791bd956f0391fadfaeca768d16bf8e742" \
  "$EXTERNAL/kontentmanager"

clone_pin \
  "SD-Offload" \
  "https://github.com/t0nyz0/SD-Offload.git" \
  "1d72b3e632f81f5ac361e077d6f9d74764b2bec3" \
  "$EXTERNAL/SD-Offload"

echo "==> applying Clip Resolved SD-Offload integration patches"
git -C "$EXTERNAL/SD-Offload" apply \
  "$ROOT/patches/SD-Offload/0001-detect-shallow-recorder-media.patch"

echo "==> installing SynthCut workspace dependencies"
(
  cd "$EXTERNAL/SynthCut"
  npm ci
)

echo "==> creating/updating Python virtualenv"
if [[ ! -d "$ROOT/.venv" ]]; then
  python3 -m venv "$ROOT/.venv"
fi
"$ROOT/.venv/bin/python" -m pip install --upgrade pip
"$ROOT/.venv/bin/python" -m pip install -e "$ROOT[dev]"

echo
printf 'Pinned upstreams ready.\n'
printf 'Activate with: source %q\n' "$ROOT/.venv/bin/activate"
printf 'Then run: clip-resolved doctor\n'
