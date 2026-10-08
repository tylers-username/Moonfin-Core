#!/usr/bin/env bash
# Experimental Moonfin 2.6.0 EGL renderer test.
# This is deliberately opt-in; it does not change the installed AppImage.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"
if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter SDK not found; install Flutter 3.47.2 and add flutter to PATH." >&2
  exit 1
fi
if ! command -v patch >/dev/null 2>&1; then
  echo "The 'patch' command is required." >&2
  exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "Python 3 is required to locate the pinned Dart dependency." >&2
  exit 1
fi

flutter pub get

# Dart pub keeps the pinned git dependency in a shared cache. Temporarily
# patch the cached native file and ALWAYS restore it after the build.
PACKAGE_PATH="$(python3 - <<'PY'
import json
from pathlib import Path
from urllib.parse import unquote, urlparse
config = Path('.dart_tool/package_config.json').resolve()
data = json.loads(config.read_text())
pkg = next((p for p in data['packages'] if p['name'] == 'media_kit_video'), None)
if pkg is None:
    raise SystemExit('media_kit_video missing after flutter pub get')
uri = pkg['rootUri']
parsed = urlparse(uri)
if parsed.scheme == 'file':
    path = Path(unquote(parsed.path))
elif not parsed.scheme:
    path = (config.parent / unquote(uri)).resolve()
else:
    raise SystemExit(f'Unsupported package URI: {uri}')
print(path)
PY
)"
SOURCE="$PACKAGE_PATH/linux/video_output.cc"
PATCH="$REPO_ROOT/patches/media-kit-video-linux-egl.patch"
if [ ! -f "$SOURCE" ]; then
  echo "Pinned media_kit_video source not found at: $SOURCE" >&2
  exit 1
fi
if ! patch --dry-run --batch --forward --fuzz=0 -d "$PACKAGE_PATH" -p1 < "$PATCH"; then
  echo "Dependency differs from the pinned media_kit_video fork; refusing to patch." >&2
  exit 1
fi

BACKUP="$(mktemp)"
cp -p "$SOURCE" "$BACKUP"
restore() {
  cp -p "$BACKUP" "$SOURCE"
  rm -f "$BACKUP"
}
trap restore EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

patch --batch --forward --fuzz=0 -d "$PACKAGE_PATH" -p1 < "$PATCH"
echo "Applied experimental EGL patch to media_kit_video in pub cache."
echo "Building Moonfin Linux bundle; original dependency will be restored afterward."
flutter build linux --release
echo
echo "Bundle built at: $REPO_ROOT/build/linux/x64/release/bundle"
echo "Run the bundle's 'moonfin' binary for testing. Do not overwrite your existing AppImage yet."
