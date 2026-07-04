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
  if [[ -d "$ROOT_DIR/resource_hd" ]]; then
    cp -a "$ROOT_DIR/resource_hd" "$DIST_DIR/resource_hd"
  fi

  if [[ -d "$ROOT_DIR/assets" ]]; then
    cp -a "$ROOT_DIR/assets" "$DIST_DIR/assets"
  fi

  if [[ -d "$ROOT_DIR/skin_catalog" ]]; then
    cp -a "$ROOT_DIR/skin_catalog" "$DIST_DIR/skin_catalog"
  fi

  if [[ -d "$ROOT_DIR/skin_store" ]]; then
    cp -a "$ROOT_DIR/skin_store" "$DIST_DIR/skin_store"
  fi

  if [[ -d "$ROOT_DIR/companion_console" ]]; then
    cp -a "$ROOT_DIR/companion_console" "$DIST_DIR/companion_console"
  fi

  mkdir -p "$DIST_DIR/scripts"
  cp "$ROOT_DIR/scripts/pet_helper.py" "$DIST_DIR/scripts/pet_helper.py"
  cp "$ROOT_DIR/scripts/import_shimeji_skin.py" "$DIST_DIR/scripts/import_shimeji_skin.py"
  cp "$ROOT_DIR/scripts/skin_sdk.py" "$DIST_DIR/scripts/skin_sdk.py"
  cp "$ROOT_DIR/scripts/cachomon_catalog.py" "$DIST_DIR/scripts/cachomon_catalog.py"
  cp "$ROOT_DIR/scripts/skin_store_server.py" "$DIST_DIR/scripts/skin_store_server.py"
  cp "$ROOT_DIR/scripts/fetch_featured_skins.py" "$DIST_DIR/scripts/fetch_featured_skins.py"
  chmod +x "$DIST_DIR/scripts/pet_helper.py"
  if [[ ! -x "$ROOT_DIR/build/helper/pet_helper" \
      || "$ROOT_DIR/scripts/pet_helper.py" -nt "$ROOT_DIR/build/helper/pet_helper" \
      || "$ROOT_DIR/scripts/import_shimeji_skin.py" -nt "$ROOT_DIR/build/helper/pet_helper" \
      || "$ROOT_DIR/scripts/skin_sdk.py" -nt "$ROOT_DIR/build/helper/pet_helper" \
      || "$ROOT_DIR/scripts/cachomon_catalog.py" -nt "$ROOT_DIR/build/helper/pet_helper" \
      || "$ROOT_DIR/scripts/skin_store_server.py" -nt "$ROOT_DIR/build/helper/pet_helper" ]]; then
    if command -v pyinstaller >/dev/null 2>&1; then
      pyinstaller --onefile --clean --name pet_helper \
        --distpath "$ROOT_DIR/build/helper" \
        --workpath "$ROOT_DIR/build/pyinstaller" \
        --specpath "$ROOT_DIR/build/spec" \
        "$ROOT_DIR/scripts/pet_helper.py"
    elif [[ -x "$ROOT_DIR/.venv/bin/pyinstaller" ]]; then
      "$ROOT_DIR/.venv/bin/pyinstaller" --onefile --clean --name pet_helper \
        --distpath "$ROOT_DIR/build/helper" \
        --workpath "$ROOT_DIR/build/pyinstaller" \
        --specpath "$ROOT_DIR/build/spec" \
        "$ROOT_DIR/scripts/pet_helper.py"
    fi
  fi
  if [[ -x "$ROOT_DIR/build/helper/pet_helper" ]]; then
    cp "$ROOT_DIR/build/helper/pet_helper" "$DIST_DIR/scripts/pet_helper"
    chmod +x "$DIST_DIR/scripts/pet_helper"
  else
    echo "pet_helper binary was not built; development bundle will use pet_helper.py if Python is available." >&2
  fi
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
