#!/usr/bin/env bash
set -euo pipefail

pkill -f 'MascotMateDesktop|GodotPetRuntime|Godot_v.*godot_pet' || true
