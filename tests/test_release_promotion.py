from __future__ import annotations

import hashlib
import json
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
from prepare_release import prepare, STABLE_ARCHIVES

COMMIT = "a" * 40


class ReleasePromotionTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        for target, filename in STABLE_ARCHIVES.items():
            self.write_candidate(target, filename)

    def write_candidate(self, target, filename, *, dirty=False):
        archive = self.root / filename
        with zipfile.ZipFile(archive, "w") as zf:
            zf.writestr("BUILD_INFO.json", json.dumps({"version": "1.3.0", "commit": COMMIT, "target": target, "public": True, "candidate": False, "dirty": dirty}))
        digest = hashlib.sha256(archive.read_bytes()).hexdigest()
        archive.with_suffix(".zip.sha256").write_text(f"{digest}  {filename}\n")
        (self.root / f"acceptance-{target}.json").write_text(json.dumps({"version": "1.3.0", "commit": COMMIT, "target": target, "passed": True, "archive": filename, "sha256": digest, "helper": True, "skin_import": True, "skin_store": True, "companion_console": True, "restart": True, "app": {"version": "1.3.0", "passed": True, "checks": {f"check-{index}": True for index in range(18)}}}))

    def test_promotes_the_exact_accepted_bytes(self):
        before = {p.name: p.read_bytes() for p in self.root.glob("*.zip")}
        notes = prepare(self.root, "1.3.0", COMMIT)
        self.assertIn("macOS", notes)
        self.assertEqual(before, {p.name: p.read_bytes() for p in self.root.glob("*.zip")})
        self.assertEqual(len((self.root / "SHA256SUMS.txt").read_text().splitlines()), 2)

    def test_rejects_archive_replaced_after_acceptance(self):
        with (self.root / STABLE_ARCHIVES["windows"]).open("ab") as output:
            output.write(b"changed")
        with self.assertRaisesRegex(ValueError, "Checksum"):
            prepare(self.root, "1.3.0", COMMIT)

    def test_rejects_missing_or_incomplete_acceptance(self):
        path = self.root / "acceptance-linux.json"
        report = json.loads(path.read_text())
        report["app"]["checks"]["check-0"] = False
        path.write_text(json.dumps(report))
        with self.assertRaisesRegex(ValueError, "desktop acceptance"):
            prepare(self.root, "1.3.0", COMMIT)
        path.unlink()
        with self.assertRaises(FileNotFoundError):
            prepare(self.root, "1.3.0", COMMIT)

    def test_rejects_macos_assets_dirty_sources_and_wrong_commits(self):
        extra = self.root / "MascotMateDesktop-macos-arm64-candidate.zip"
        extra.write_bytes(b"candidate")
        with self.assertRaisesRegex(ValueError, "exactly"):
            prepare(self.root, "1.3.0", COMMIT)
        extra.unlink()
        with self.assertRaisesRegex(ValueError, "mismatch"):
            prepare(self.root, "1.3.0", "b" * 40)
        self.write_candidate("linux", STABLE_ARCHIVES["linux"], dirty=True)
        with self.assertRaisesRegex(ValueError, "Unqualified"):
            prepare(self.root, "1.3.0", COMMIT)


if __name__ == "__main__":
    unittest.main()
