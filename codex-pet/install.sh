#!/usr/bin/env bash
set -euo pipefail

EXPECTED_SHA256="f7a5a2cf2d1995590720024d1738bb916fc80255dbea8be4e058fa249c6a7ed3"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODEX_DATA_DIR="${CODEX_HOME:-$HOME/.codex}"
TARGET_DIR="$CODEX_DATA_DIR/pets/black-sentinel"
SPRITE="$SCRIPT_DIR/spritesheet.png"
MANIFEST="$SCRIPT_DIR/pet.json"
BUILD_VENV=""

cleanup() {
  if [[ -n "$BUILD_VENV" && -d "$BUILD_VENV" ]]; then
    rm -rf "$BUILD_VENV"
  fi
}
trap cleanup EXIT

if [[ ! -f "$MANIFEST" ]]; then
  printf 'Package is incomplete: pet.json is missing.\n' >&2
  exit 1
fi

if [[ ! -f "$SPRITE" ]]; then
  if command -v python3 >/dev/null 2>&1; then
    PYTHON=python3
  elif command -v python >/dev/null 2>&1; then
    PYTHON=python
  else
    printf 'Python 3 is required to build the sprite atlas.\n' >&2
    exit 1
  fi

  BUILD_VENV="$(mktemp -d "${TMPDIR:-/tmp}/black-sentinel.XXXXXX")"
  "$PYTHON" -m venv "$BUILD_VENV"
  "$BUILD_VENV/bin/python" -m pip install --disable-pip-version-check -r "$SCRIPT_DIR/requirements.txt"
  "$BUILD_VENV/bin/python" "$SCRIPT_DIR/generate_spritesheet.py"
fi

if command -v sha256sum >/dev/null 2>&1; then
  actual_sha="$(sha256sum "$SPRITE" | awk '{print $1}')"
else
  actual_sha="$(shasum -a 256 "$SPRITE" | awk '{print $1}')"
fi

if [[ "$actual_sha" != "$EXPECTED_SHA256" ]]; then
  printf 'Spritesheet checksum mismatch: %s\n' "$actual_sha" >&2
  exit 1
fi

mkdir -p "$TARGET_DIR"
install -m 0644 "$MANIFEST" "$TARGET_DIR/pet.json"
install -m 0644 "$SPRITE" "$TARGET_DIR/spritesheet.png"

printf 'Installed BLACK Sentinel to %s\n' "$TARGET_DIR"
printf 'Restart Codex, then select BLACK Sentinel from custom pets.\n'
