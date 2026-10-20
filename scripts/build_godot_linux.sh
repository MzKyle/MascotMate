#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist/MascotMateDesktop"
GODOT_BIN_PATH="$("$ROOT_DIR/scripts/setup_godot.sh" | tail -n 1)"
USE_EXPORT="${GODOT_EXPORT:-0}"
TEMPLATE_VERSION="${GODOT_VERSION:-4.6.3-stable}"
TEMPLATE_VERSION="${TEMPLATE_VERSION/-stable/.stable}"
TEMPLATE_DIR="${GODOT_EXPORT_TEMPLATE_DIR:-$HOME/.local/share/godot/export_templates/$TEMPLATE_VERSION}"

if [[ "${1:-}" == "--export" ]]; then
  USE_EXPORT=1
fi

if [[ ! -x "$GODOT_BIN_PATH" ]]; then
  echo "Godot executable not found: $GODOT_BIN_PATH" >&2
  exit 1
fi

python3 "$ROOT_DIR/scripts/generate_godot_manifest.py"

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

copy_external_assets() {
  python3 - "$ROOT_DIR" "$DIST_DIR" <<'PY'
import sys
from pathlib import Path
sys.path.insert(0, str(Path(sys.argv[1]) / "scripts"))
from build_portable import build_helper, copy_external_assets
copy_external_assets(Path(sys.argv[2]), build_helper())
PY
}

if [[ "$USE_EXPORT" == "1" ]]; then
  if [[ ! -f "$TEMPLATE_DIR/linux_debug.x86_64" || ! -f "$TEMPLATE_DIR/linux_release.x86_64" ]]; then
    echo "Godot export templates are missing:" >&2
    echo "  $TEMPLATE_DIR/linux_debug.x86_64" >&2
    echo "  $TEMPLATE_DIR/linux_release.x86_64" >&2
    echo "" >&2
    echo "Install them with:" >&2
    echo "  scripts/setup_godot_export_templates.sh" >&2
    echo "" >&2
    echo "Or build the already-supported portable bundle with:" >&2
    echo "  scripts/build_godot_linux.sh" >&2
    exit 1
  fi

  echo "Trying Godot Linux export..."
  if "$GODOT_BIN_PATH" --headless --path "$ROOT_DIR/godot_pet" --export-release "Linux" "$DIST_DIR/MascotMateDesktop"; then
    copy_external_assets
    chmod +x "$DIST_DIR/MascotMateDesktop"
    echo "Built Godot export: $DIST_DIR/MascotMateDesktop"
    exit 0
  fi
  echo "Godot export failed. Install export templates or run without --export for the portable bundle." >&2
  exit 1
fi

cp "$GODOT_BIN_PATH" "$DIST_DIR/GodotPetRuntime"
cp -a "$ROOT_DIR/godot_pet" "$DIST_DIR/godot_pet"
copy_external_assets

cat > "$DIST_DIR/MascotMateDesktop" <<'LAUNCHER'
#!/usr/bin/env bash
set -euo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export CRAYON_PET_ROOT="$APP_DIR"
export CRAYON_PET_TRANSPARENT="${CRAYON_PET_TRANSPARENT:-1}"
export CRAYON_PET_ALWAYS_ON_TOP="${CRAYON_PET_ALWAYS_ON_TOP:-1}"
export CRAYON_PET_BORDERLESS="${CRAYON_PET_BORDERLESS:-1}"
export CRAYON_PET_MOUSE_PASSTHROUGH="${CRAYON_PET_MOUSE_PASSTHROUGH:-1}"
exec "$APP_DIR/GodotPetRuntime" --path "$APP_DIR/godot_pet" "$@"
LAUNCHER

chmod +x "$DIST_DIR/GodotPetRuntime" "$DIST_DIR/MascotMateDesktop"

echo "Built Godot portable bundle: $DIST_DIR/MascotMateDesktop"
echo "This bundle uses the official Godot runtime directly; install export templates later if you want a smaller .pck-style export."
