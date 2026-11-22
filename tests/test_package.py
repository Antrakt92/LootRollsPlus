"""Check archive identity and contents from a differently named checkout."""

from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from zipfile import ZipFile


class PackageTest(unittest.TestCase):
    def test_checkout_name_does_not_change_installed_addon_name(self):
        source = Path(__file__).resolve().parents[1]
        toc = source / "LootRollsPlus.toc"
        metadata = toc.read_text(encoding="utf-8")
        version = re.search(r"^## Version: (\S+)$", metadata, re.MULTILINE).group(1)
        files = ["LootRollsPlus.toc", "LICENSE", "README.md", "CHANGELOG.md",
                 "media/addon-icon.png", *re.findall(r"^\w+\.lua$", metadata, re.MULTILINE)]
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "review-checkout"
            for name in [*files, "tests/package.py"]:
                target = root / name
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(source / name, target)

            archive = Path(temporary) / f"LootRollsPlus-{version}.zip"
            subprocess.run([sys.executable, root / "tests/package.py", archive],
                           capture_output=True, check=True)
            with ZipFile(archive) as bundle:
                self.assertCountEqual(bundle.namelist(), [f"LootRollsPlus/{name}" for name in files])
                for name in files:
                    self.assertEqual(bundle.read(f"LootRollsPlus/{name}"), (source / name).read_bytes())


if __name__ == "__main__":
    unittest.main()
