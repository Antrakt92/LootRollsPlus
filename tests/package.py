"""Build an installable preview ZIP from the addon directory."""

import argparse
from pathlib import Path
import re
from tempfile import TemporaryDirectory
from zipfile import ZIP_DEFLATED, ZipFile, ZipInfo


ADDON_NAME = "LootRollsPlus"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()

    root = Path(__file__).resolve().parents[1]
    toc = root / f"{ADDON_NAME}.toc"
    metadata = toc.read_text(encoding="utf-8")
    version = re.search(r"^## Version: ([0-9A-Za-z.-]+)$", metadata, re.MULTILINE)
    if not version:
        parser.error("The TOC must declare a version.")
    archive = args.output.resolve()
    expected_name = f"{ADDON_NAME}-{version.group(1)}.zip"
    if archive.name != expected_name:
        parser.error(f"Expected {expected_name}.")
    modules = [
        line.strip()
        for line in metadata.splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    ]
    if not modules or len(modules) != len({name.casefold() for name in modules}) or not all(
        re.fullmatch(r"[A-Za-z][A-Za-z0-9]*\.lua", name) for name in modules
    ):
        parser.error("Expected unique Lua modules in the TOC.")
    names = [
        toc.name, *modules, "LICENSE", "README.md", "CHANGELOG.md",
        "media/addon-icon.png",
    ]
    expected = {f"{ADDON_NAME}/{name}": (root / name).read_bytes() for name in names}
    archive.parent.mkdir(parents=True, exist_ok=True)
    with TemporaryDirectory(prefix=".loot-rolls-plus-", dir=archive.parent) as staging:
        candidate = Path(staging) / archive.name
        with ZipFile(candidate, "w", compression=ZIP_DEFLATED) as bundle:
            for name, source in expected.items():
                bundle.writestr(ZipInfo(name), source, compress_type=ZIP_DEFLATED)
        with ZipFile(candidate) as bundle:
            if bundle.namelist() != list(expected) or bundle.testzip() is not None:
                raise RuntimeError("The package layout or ZIP checksum is invalid.")
            for name, source in expected.items():
                if bundle.read(name) != source:
                    raise RuntimeError(f"The package differs from source for {name}.")
        candidate.replace(archive)
    print(archive)


if __name__ == "__main__":
    main()
