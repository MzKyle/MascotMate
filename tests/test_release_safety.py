from __future__ import annotations

import importlib.util
import io
import json
import os
import plistlib
import stat
import subprocess
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest.mock import patch

SCRIPTS = Path(__file__).resolve().parents[1] / "scripts"
sys.path.insert(0, str(SCRIPTS))
import app_paths
import catalog_policy
import package_archive
import release_version
import skin_sdk
import pet_helper
import build_portable


class ReleaseSafetyTests(unittest.TestCase):
    def test_macos_export_normalizes_godot_bundle_name_and_restores_execute_permission(self):
        with tempfile.TemporaryDirectory() as directory:
            package = Path(directory)
            def godot_export(command):
                with zipfile.ZipFile(command[-1], "w") as archive:
                    archive.writestr("MascotMate Desktop.app/Contents/Info.plist", plistlib.dumps({"CFBundleExecutable": "MascotMate Desktop"}))
                    program = zipfile.ZipInfo("MascotMate Desktop.app/Contents/MacOS/MascotMate Desktop")
                    program.create_system = 3
                    program.external_attr = (stat.S_IFREG | 0o644) << 16
                    archive.writestr(program, b"exported executable")
            with patch.object(build_portable, "find_godot", return_value="godot"), patch.object(build_portable, "run", side_effect=godot_export):
                build_portable.export_project("macos", package)
            program = package / "MascotMateDesktop.app/Contents/MacOS/MascotMate Desktop"
            self.assertEqual(program.read_bytes(), b"exported executable")
            self.assertFalse((package / "MascotMate Desktop.app").exists())
            self.assertFalse((package / "MascotMateDesktop.zip").exists())
            if os.name != "nt":
                self.assertTrue(program.stat().st_mode & stat.S_IXUSR)

    @unittest.skipUnless(hasattr(os, "fork"), "Requires a POSIX clipboard-owner process")
    def test_clipboard_owner_does_not_keep_helper_output_pipe_open(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            xclip = root / "xclip"
            xclip.write_text(f"#!{sys.executable}\nimport os, sys, time\nsys.stdin.buffer.read()\nif os.fork() == 0:\n    time.sleep(5)\n    os._exit(0)\n", encoding="utf-8")
            xclip.chmod(0o755)
            image = root / "image.png"
            image.write_bytes(b"clipboard fixture")
            env = os.environ.copy()
            env.update({"PATH": str(root), "PYTHONPATH": str(SCRIPTS)})
            # A background clipboard owner inheriting stdout would block this
            # captured helper invocation until it exits, just like Godot OS.execute.
            result = subprocess.run([sys.executable, "-c", "import sys, pet_helper; sys.exit(pet_helper.copy_image_linux(__import__('pathlib').Path(sys.argv[1])))", str(image)], env=env, capture_output=True, timeout=3)
            self.assertEqual(result.returncode, 0, result.stderr)

    def test_helper_protocol_is_utf8_on_english_windows(self):
        output = io.BytesIO()
        stream = io.TextIOWrapper(output, encoding="cp1252")
        try:
            with patch.object(sys, "stdout", stream), patch.object(sys, "stderr", stream):
                pet_helper.configure_stdio()
                print(json.dumps({"path": "全新 data/皮肤"}, ensure_ascii=False))
                stream.flush()
            self.assertEqual(json.loads(output.getvalue().decode("utf-8"))["path"], "全新 data/皮肤")
        finally:
            stream.detach()

    def test_platform_paths_and_override_precedence(self):
        with patch.dict(os.environ, {}, clear=True), patch("pathlib.Path.home", return_value=Path("/home/test")):
            with patch.object(sys, "platform", "linux"):
                self.assertEqual(app_paths.data_dir(), Path("/home/test/.local/share/mascotmate-desktop"))
                with patch.dict(os.environ, {"XDG_DATA_HOME": "/data home"}):
                    self.assertEqual(app_paths.data_dir(), Path("/data home/mascotmate-desktop"))
            with patch.object(sys, "platform", "darwin"):
                self.assertEqual(app_paths.data_dir(), Path("/home/test/Library/Application Support/mascotmate-desktop"))
            with patch.object(sys, "platform", "win32"), patch.dict(os.environ, {"APPDATA": "C:/Roaming"}):
                self.assertEqual(app_paths.data_dir(), Path("C:/Roaming/mascotmate-desktop"))
            with patch.dict(os.environ, {"CRAYON_PET_CONFIG_DIR": str(SCRIPTS / "中文 data")}):
                self.assertEqual(app_paths.data_dir(), (SCRIPTS / "中文 data").resolve())
                self.assertEqual(app_paths.data_dir(SCRIPTS / "explicit"), (SCRIPTS / "explicit").resolve())

    def test_config_frame_root_respects_explicit_directory(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            with patch.dict(os.environ, {"CRAYON_PET_CONFIG_DIR": str(root / "environment")}):
                manifest = {"frame_root": "$config/skins/test/frames"}
                self.assertEqual(skin_sdk.resolve_frame_root(manifest, root / "skin.json", root), root / "environment/skins/test/frames")
                self.assertEqual(skin_sdk.resolve_frame_root(manifest, root / "skin.json", root, root / "explicit"), root / "explicit/skins/test/frames")

    def test_public_catalog_copies_only_explicitly_allowed_references(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "source"
            source.mkdir()
            entries = []
            for skin_id, permission in [("allowed", True), ("private", False), ("string", "true"), ("missing", None)]:
                entry = {"id": skin_id, "source_type": "local_package", "license": {"redistributable": permission}, "package": f"packages/{skin_id}.zip", "preview": f"previews/{skin_id}.png"}
                entries.append(entry)
                for key in ("package", "preview"):
                    asset = source / entry[key]
                    asset.parent.mkdir(exist_ok=True)
                    asset.write_bytes(skin_id.encode())
            (source / "packages/orphan.zip").write_bytes(b"private")
            (source / "catalog.json").write_text(json.dumps({"skins": entries}))
            (source / "cachomon_index.json").write_text('{"entries": []}')
            staged = Path(directory) / "public"
            catalog_policy.stage_public_catalog(source, staged)
            self.assertEqual([e["id"] for e in json.loads((staged / "catalog.json").read_text())["skins"]], ["allowed"])
            self.assertEqual(sorted(p.name for p in (staged / "packages").iterdir()), ["allowed.zip"])
            self.assertEqual(sorted(p.name for p in (staged / "previews").iterdir()), ["allowed.png"])
            self.assertTrue((source / "packages/private.zip").is_file())
            self.assertTrue((staged / "cachomon_index.json").is_file())

    def test_empty_catalog_and_unsafe_reference(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "source"
            source.mkdir()
            (source / "catalog.json").write_text('{"skins": []}')
            catalog_policy.stage_public_catalog(source, Path(directory) / "public")
            self.assertEqual(json.loads((Path(directory) / "public/catalog.json").read_text())["skins"], [])
            for reference in ("../private.zip", "/private.zip", "C:/private.zip", "..\\private.zip"):
                with self.assertRaises(ValueError):
                    catalog_policy.catalog_asset(source, reference)

    def test_archive_executable_modes_and_symlinks_round_trip(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            archive = root / "export.zip"
            with zipfile.ZipFile(archive, "w") as zf:
                program = zipfile.ZipInfo("App.app/Contents/MacOS/App")
                program.create_system = 3
                program.external_attr = (stat.S_IFREG | 0o755) << 16
                zf.writestr(program, b"program")
                if os.name != "nt":
                    link = zipfile.ZipInfo("App.app/Contents/MacOS/link")
                    link.create_system = 3
                    link.external_attr = (stat.S_IFLNK | 0o777) << 16
                    zf.writestr(link, "App")
            unpacked = root / "unpacked"
            package_archive.extract_archive(archive, unpacked)
            final = root / "final.zip"
            package_archive.create_archive(unpacked, final)
            restored = root / "restored"
            package_archive.extract_archive(final, restored)
            executable = restored / "App.app/Contents/MacOS/App"
            self.assertEqual(executable.read_bytes(), b"program")
            if os.name != "nt":
                self.assertTrue(executable.stat().st_mode & stat.S_IXUSR)
                self.assertTrue((executable.parent / "link").is_symlink())

    def test_archive_rejects_escaping_symlink(self):
        with tempfile.TemporaryDirectory() as directory:
            archive = Path(directory) / "bad.zip"
            with zipfile.ZipFile(archive, "w") as zf:
                link = zipfile.ZipInfo("bad")
                link.external_attr = (stat.S_IFLNK | 0o777) << 16
                zf.writestr(link, "../outside")
            with self.assertRaises(ValueError):
                package_archive.extract_archive(archive, Path(directory) / "unpacked")

    def test_version_and_tag_must_agree(self):
        self.assertEqual(release_version.check_versions("v1.3.0"), "1.3.0")
        with self.assertRaises(ValueError):
            release_version.check_versions("v1.2.5")

    def test_helper_cache_tracks_sidecar_dependencies_and_architecture(self):
        spec = importlib.util.spec_from_file_location("build_cache_test", SCRIPTS / "build_portable.py")
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        with tempfile.TemporaryDirectory() as directory, patch.object(module, "ROOT", Path(directory)):
            scripts = Path(directory) / "scripts"
            scripts.mkdir()
            sidecar = scripts / "companion_ai_sidecar.py"
            sidecar.write_text("first")
            (Path(directory) / "requirements.txt").write_text("Pillow==13")
            before = module.helper_fingerprint()
            sidecar.write_text("second")
            self.assertNotEqual(before, module.helper_fingerprint())
            before = module.helper_fingerprint()
            with patch.object(module.platform, "machine", return_value="different-arch"):
                self.assertNotEqual(before, module.helper_fingerprint())
            (Path(directory) / "requirements.txt").write_text("Pillow==14")
            self.assertNotEqual(before, module.helper_fingerprint())


if __name__ == "__main__":
    unittest.main()
