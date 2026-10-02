#!/usr/bin/env python3
"""Remove resources verified to be unnecessary for the en/ja development image."""

import argparse
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
from collections import defaultdict

# These satellite cultures were checked against AssemblyName.CultureName.
SATELLITE_CULTURES = {
    "cs", "de", "es", "fr", "it", "ko", "pl", "pt-BR", "ru", "tr",
    "zh-Hans", "zh-Hant",
}
LUNR_LANGUAGES = {
    "ar", "da", "de", "du", "el", "es", "fi", "fr", "he", "hi", "hu", "hy",
    "it", "kn", "ko", "nl", "no", "pt", "ro", "ru", "sa", "sv", "ta", "te",
    "th", "tr", "vi", "zh",
}
SPEECH_LANGUAGES = {"af", "ca", "da", "de", "es", "fr", "hi", "it", "ko", "nb", "nn", "sv"}
LANGUAGE = re.compile(r"^[a-z]{2,3}(?:[-_@.][A-Za-z0-9.-]+)*$")
LOCALIZED_INKSCAPE = re.compile(
    r"\.([a-z]{2,3}(?:[_@-][A-Za-z0-9]+)*)\.(svg|png|html|xml)$"
)


def keep_language(name):
    return name in {"", "root", "C", "POSIX"} or bool(
        re.match(r"^(en|ja)(?:$|[-_@.])", name)
    )


class Compactor:
    def __init__(self):
        self.stats = defaultdict(lambda: {"files": 0, "bytes": 0})

    def remove(self, path, category):
        if path.is_symlink() or not path.is_file():
            return
        size = path.stat().st_size
        path.unlink()
        self.stats[category]["files"] += 1
        self.stats[category]["bytes"] += size

    def language_directories(self, root, category):
        for directory in root.glob("*"):
            if (
                not directory.is_symlink()
                and directory.is_dir()
                and LANGUAGE.fullmatch(directory.name)
                and not keep_language(directory.name)
            ):
                for path in directory.rglob("*"):
                    self.remove(path, category)

    def translations(self):
        for root in (
            "/usr/share/locale", "/usr/local/share/locale",
            "/opt/inkscape/usr/share/locale",
        ):
            self.language_directories(Path(root), "gettext")
        for root in ("/usr/share/man", "/usr/local/share/man"):
            self.language_directories(Path(root), "man-translations")
        for path in Path("/usr/lib64/dotnet").rglob("*.resources.dll"):
            if path.parent.name in SATELLITE_CULTURES:
                self.remove(path, "dotnet-satellites")
        for root in Path("/opt/chrome-for-testing").glob("*/chrome-linux64/locales"):
            for path in root.glob("*.pak"):
                if not keep_language(path.stem):
                    self.remove(path, "chrome-translations")
        for site in Path("/usr/local/lib").glob("python*/site-packages"):
            for path in (site / "babel/locale-data").glob("*.dat"):
                if LANGUAGE.fullmatch(path.stem) and not keep_language(path.stem):
                    self.remove(path, "babel")
            for theme in ("mkdocs", "readthedocs"):
                self.language_directories(
                    site / "mkdocs/themes" / theme / "locales", "mkdocs-translations"
                )
            for path in (site / "material/templates/partials/languages").glob("*.html"):
                if LANGUAGE.fullmatch(path.stem) and not keep_language(path.stem):
                    self.remove(path, "material-translations")
            for root in (
                site / "mkdocs/contrib/search/lunr-language",
                site / "material/templates/assets/javascripts/lunr/min",
            ):
                for path in root.glob("lunr.*.js"):
                    language = path.name[len("lunr."):-len(".js")]
                    if language.endswith(".min"):
                        language = language[:-len(".min")]
                    if language in LUNR_LANGUAGES:
                        self.remove(path, "lunr-translations")
        for subdirectory in ("tutorials", "templates"):
            root = Path("/opt/inkscape/usr/share/inkscape") / subdirectory
            for path in root.rglob("*"):
                match = LOCALIZED_INKSCAPE.search(path.name)
                if match and not keep_language(match[1]):
                    self.remove(path, "inkscape-translations")
        root = Path(
            "/usr/local/lib/node_modules/@marp-team/marp-cli/node_modules/"
            "speech-rule-engine/lib/mathmaps"
        )
        for path in root.glob("*.json"):
            if path.stem in SPEECH_LANGUAGES:
                self.remove(path, "speech-translations")

    def source_maps(self):
        for root, directories, files in os.walk("/usr/local/lib/node_modules"):
            for name in files:
                if name.endswith((".js.map", ".mjs.map", ".css.map")):
                    self.remove(Path(root) / name, "node-source-maps")

    def bytecode(self):
        for prefix in ("/usr", "/opt"):
            for root, directories, files in os.walk(prefix):
                for name in files:
                    if not name.endswith(".pyc"):
                        continue
                    path = Path(root) / name
                    try:
                        source = Path(importlib.util.source_from_cache(str(path)))
                    except ValueError:
                        source = path.with_suffix(".py")
                    if source.is_file():
                        self.remove(path, "python-bytecode")

    def git_debug(self):
        git_core = Path("/usr/local/libexec/git-core")
        groups = defaultdict(list)
        paths = [*Path("/usr/local/bin").glob("*"), *git_core.glob("*")]
        # Collect all aliases before overlayfs can copy a file into the upper layer.
        for path in paths:
            if path.is_symlink() or not path.is_file():
                continue
            stat = path.stat()
            groups[(stat.st_dev, stat.st_ino)].append(path)
        for aliases in groups.values():
            if not any(path.parent == git_core or path == Path("/usr/local/bin/git") for path in aliases):
                continue
            path = aliases[0]
            stat = path.stat()
            with path.open("rb") as source:
                if source.read(4) != b"\x7fELF":
                    continue
            with tempfile.TemporaryDirectory(prefix="compact-git-") as temporary:
                stripped = Path(temporary) / "stripped"
                subprocess.run(
                    ["strip", "--strip-debug", "-o", str(stripped), str(path)], check=True
                )
                with stripped.open("rb") as source, path.open("wb") as destination:
                    shutil.copyfileobj(source, destination)
                current = path.stat()
                for alias in aliases[1:]:
                    linked = alias.stat()
                    if (linked.st_dev, linked.st_ino) != (current.st_dev, current.st_ino):
                        alias.unlink()
                        os.link(path, alias)
                os.utime(path, ns=(stat.st_atime_ns, stat.st_mtime_ns))
                self.stats["git-debug"]["files"] += 1
                self.stats["git-debug"]["bytes"] += stat.st_size - current.st_size


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("phase", choices=("base", "packages", "git", "all"))
    phase = parser.parse_args().phase
    compactor = Compactor()
    compactor.translations()
    if phase in {"base", "all"}:
        compactor.source_maps()
    if phase in {"base", "packages", "all"}:
        compactor.bytecode()
    if phase in {"git", "all"}:
        compactor.git_debug()
    print(json.dumps({"phase": phase, "removed": compactor.stats}, sort_keys=True))


if __name__ == "__main__":
    main()
