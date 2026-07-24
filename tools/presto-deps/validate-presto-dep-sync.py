#!/usr/bin/env python3

# ruff: noqa: D102, D103, T201, S314, S607, FURB188, UP006, UP021, UP022, UP035, UP045
# D102/D103: compact CLI tool; the module docstring documents it. S314/S607: trusted
# sources, git from PATH. FURB188/UP*: kept compatible with Python 3.6, the packaging
# build-env container's interpreter.

"""
Validates this repository's dependency pins against the Presto commit pinned by
G_PRESTO_GIT_TAG (taskfile.yaml):

* pom.xml jackson/slice pins vs the Presto root pom's dep.*.version. Presto's plugin
  classloader loads these from the Presto runtime, so a mismatch crashes the coordinator.
* pom.xml presto.version vs the pinned commit's own version, whose unpublished artifacts
  tools/presto-deps/install-presto-artifacts.sh builds from source.
* taskfiles/velox-connector/deps.yaml G_*_VERSION pins vs the pinned commit's
  presto-native-execution/velox submodule tree (locations and patterns in Velox.PINS).

Prints OK/FAIL per pin with a suggested value on failure and exits non-zero; never edits
anything. Sources come from two clones under the build directory, populated with blobless
shallow fetches on first use: presto-src (shared with install-presto-artifacts.sh) and
velox-src (cloned from the submodule URL in Presto's own .gitmodules). Runs on
Python 3.6+ (the packaging build-env container ships 3.6.8).
"""

import os
import re
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Dict, NamedTuple, NoReturn, Optional, Tuple

REPO_ROOT = Path(__file__).resolve().parents[2]
ROOT_TASKFILE = REPO_ROOT / "taskfile.yaml"
BUILD_DIR = Path(os.environ.get("CLP_PLUGIN_BUILD_DIR", str(REPO_ROOT / "build")))


# ── Output ────────────────────────────────────────────────────────────────────


class Reporter:
    """Prints per-pin results and counts how many checks ran and failed."""

    _COLORED = sys.stdout.isatty() and not os.environ.get("NO_COLOR")
    _GREEN, _RED, _BOLD, _RESET = (
        ("\033[32m", "\033[31m", "\033[1m", "\033[0m") if _COLORED else ("", "", "", "")
    )

    def __init__(self) -> None:
        self.checks = 0
        self.failures = 0

    def header(self, text: str) -> None:
        print(self._BOLD + text + self._RESET)

    def ok(self, text: str) -> None:
        self.checks += 1
        print(f"  {self._GREEN}OK{self._RESET}   {text}")

    def fail(self, text: str, suggestion: str) -> None:
        self.checks += 1
        self.failures += 1
        print(f"  {self._RED}FAIL{self._RESET} {text}")
        print("       Suggestion: " + suggestion)


def die(message: str) -> NoReturn:
    print("ERROR: " + message, file=sys.stderr)
    sys.exit(1)


# ── Git helpers ───────────────────────────────────────────────────────────────


def _git(cwd: Path, *args: str) -> "subprocess.CompletedProcess":
    return subprocess.run(
        ["git", "-C", str(cwd), *args],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        universal_newlines=True,
        check=False,
    )


def run_git(cwd: Path, *args: str) -> Optional[str]:
    result = _git(cwd, *args)
    return result.stdout.strip() if result.returncode == 0 else None


def git_or_die(cwd: Path, *args: str) -> str:
    result = _git(cwd, *args)
    if result.returncode != 0:
        die(f"git {' '.join(args)} failed in {cwd}: {result.stderr.strip()}")
    return result.stdout.strip()


def shallow_repo(directory: Path, git_url: str, commit: str) -> Path:
    """
    Ensure a repo under the build dir contains `commit`, fetching it when absent.

    Blobless (--filter=blob:none) keeps the fetch small: git downloads commits and trees
    up front, and each file's content on demand when it is first read.
    """
    directory.mkdir(parents=True, exist_ok=True)
    if not (directory / ".git").is_dir():
        git_or_die(directory, "init", "--quiet")
        git_or_die(directory, "remote", "add", "origin", git_url)
    git_or_die(directory, "remote", "set-url", "origin", git_url)
    if run_git(directory, "cat-file", "-e", commit + "^{commit}") is None:
        print(f"==> Fetching {git_url} at {commit[:12]} (blobless)...")
        git_or_die(directory, "fetch", "--depth", "1", "--filter=blob:none", "origin", commit)
    return directory


def git_show(repo: Path, commit: str, rel_path: str) -> str:
    return git_or_die(repo, "show", f"{commit}:{rel_path}")


# ── File parsing ──────────────────────────────────────────────────────────────


class Pom(NamedTuple):
    """A parsed Maven pom: its properties, its own project version, and a display label."""

    props: Dict[str, str]
    version: Optional[str]
    label: str


def parse_pom(xml_text: str, label: str) -> Pom:
    try:
        root = ET.fromstring(xml_text)
    except ET.ParseError as error:
        die(f"failed to parse {label}: {error}")
    props, version = {}, None
    for child in root:
        # ElementTree prefixes each tag with its XML namespace as "{uri}tag"; strip it.
        tag = child.tag.rsplit("}", 1)[-1]
        if tag == "properties":
            props = {p.tag.rsplit("}", 1)[-1]: (p.text or "").strip() for p in child}
        elif tag == "version":
            version = (child.text or "").strip()
    return Pom(props, version, label)


def prop(pom: Pom, name: str) -> str:
    value = pom.props.get(name, "")
    if not value:
        die(f"property <{name}> not found in {pom.label}")
    return value


def yaml_var(text: str, name: str, path: Path) -> str:
    match = re.search(rf'^\s*{re.escape(name)}: "([^"]*)"', text, re.MULTILINE)
    if not match:
        die(f"{name} not found in {path}")
    return match.group(1)


# ── Pinned sources ────────────────────────────────────────────────────────────


def presto_pin() -> Tuple[str, str]:
    """Return (git_url, commit) for the pinned Presto from the root taskfile."""
    if not ROOT_TASKFILE.is_file():
        die("file not found: " + str(ROOT_TASKFILE))
    text = ROOT_TASKFILE.read_text()
    return (
        yaml_var(text, "G_PRESTO_GIT_URL", ROOT_TASKFILE),
        yaml_var(text, "G_PRESTO_GIT_TAG", ROOT_TASKFILE),
    )


def presto_clone(git_url: str, pin: str) -> Path:
    """
    Return the Presto-side clone (shared with install-presto-artifacts.sh), fetching the
    pinned commit into it when absent: whichever tool runs first seeds it for the others.
    """
    return shallow_repo(BUILD_DIR / "presto-src", git_url, pin)


# ── Checks ────────────────────────────────────────────────────────────────────


def strip_v(version: str) -> str:
    """Drop a leading "v" so versions compare across tag-prefix styles."""
    return version[1:] if version.startswith("v") else version


class Presto:
    """
    The pinned Presto commit (G_PRESTO_GIT_URL / G_PRESTO_GIT_TAG in taskfile.yaml): a
    local clone containing it, its root pom, and the checks that keep
    presto-connector/pom.xml's Presto-synced pins matching that pom.
    """

    CONNECTOR_POM = REPO_ROOT / "presto-connector" / "pom.xml"

    def __init__(self) -> None:
        if not self.CONNECTOR_POM.is_file():
            die("file not found: " + str(self.CONNECTOR_POM))
        git_url, self.pin = presto_pin()
        self.connector_pom = parse_pom(self.CONNECTOR_POM.read_text(), str(self.CONNECTOR_POM))
        repo = presto_clone(git_url, self.pin)
        self.root_pom = parse_pom(
            git_show(repo, self.pin, "pom.xml"), f"presto@{self.pin[:9]} pom.xml"
        )
        if not self.root_pom.version:
            die("project version not found in " + self.root_pom.label)

    def check(self, report: Reporter) -> None:
        """Check pom.xml's Presto-synced pins against the pinned commit's root pom."""
        pin = self.pin
        report.header(f"Presto (presto@{pin[:12]}, {self.root_pom.version})")

        # Presto manages third-party versions centrally in its root pom's
        # <dependencyManagement> (the dep.* properties); modules such as presto-spi
        # declare these dependencies without versions, so the root pom is the source of
        # truth for what the Presto runtime ships.
        for name, theirs in (
            ("jackson.version", prop(self.root_pom, "dep.jackson.version")),
            ("slice.version", prop(self.root_pom, "dep.slice.version")),
        ):
            ours = prop(self.connector_pom, name)
            if ours == theirs:
                report.ok(f"{name}: {ours}")
            else:
                report.fail(f"{name}: pom.xml pins {ours} but presto@{pin[:9]} ships {theirs}",
                            f"set <{name}> to {theirs} in presto-connector/pom.xml.")

        # jackson-annotations sometimes publishes a 2-segment version paired with a
        # 3-segment core/databind family (e.g. annotations 2.22 with core 2.22.0), so
        # accept an exact match or a major.minor prefix match.
        ours = prop(self.connector_pom, "jackson.annotations.version")
        theirs = prop(self.root_pom, "dep.jackson.version")
        if ours == theirs or theirs.startswith(ours + "."):
            report.ok("jackson.annotations.version: " + ours)
        else:
            report.fail(f"jackson.annotations.version: pom.xml pins {ours} but"
                        f" presto@{pin[:9]} ships {theirs}",
                        f"set <jackson.annotations.version> to {theirs} in"
                        " presto-connector/pom.xml.")

        # presto.version must be the pinned commit's own version; its unpublished
        # artifacts are built from source by install-presto-artifacts.sh.
        ours = prop(self.connector_pom, "presto.version")
        theirs = self.root_pom.version
        if ours == theirs:
            report.ok("presto.version: " + ours)
        else:
            report.fail(f"presto.version: pom.xml pins {ours} but presto@{pin[:9]} is"
                        f" version {theirs}",
                        f"set <presto.version> to {theirs} in presto-connector/pom.xml,"
                        " then build its artifacts with"
                        " tools/presto-deps/install-presto-artifacts.sh.")


class Velox:
    """
    The Velox tree the pinned Presto commit builds with (its
    presto-native-execution/velox submodule): a local clone containing it, and the checks
    that keep deps.yaml's G_*_VERSION pins matching that tree.
    """

    DEPS_YAML = REPO_ROOT / "taskfiles" / "velox-connector" / "deps.yaml"
    SUBMODULE = "presto-native-execution/velox"

    # deps.yaml variable -> (file in the Velox tree, version-extraction pattern).
    CMAKE_MODULES = "CMake/resolve_dependency_modules"
    PINS = (
        ("G_DOUBLE_CONVERSION_VERSION", "CMakeLists.txt",
         r"find_package\(double-conversion\s+([\d.]+)\s+REQUIRED"),
        ("G_FAST_FLOAT_VERSION", CMAKE_MODULES + "/fastfloat.cmake",
         r'set\(VELOX_FASTFLOAT_VERSION\s+"?([^)"\s]+)"?\)'),
        ("G_FMT_VERSION", CMAKE_MODULES + "/fmt.cmake",
         r'set\(VELOX_FMT_VERSION\s+"?([^)"\s]+)"?\)'),
        ("G_FOLLY_VERSION", CMAKE_MODULES + "/folly/CMakeLists.txt",
         r'set\(VELOX_FOLLY_BUILD_VERSION\s+"?([^)"\s]+)"?\)'),
        ("G_GFLAGS_VERSION", CMAKE_MODULES + "/gflags.cmake",
         r'set\(VELOX_GFLAGS_VERSION\s+"?([^)"\s]+)"?\)'),
        ("G_GLOG_VERSION", CMAKE_MODULES + "/glog.cmake",
         r'set\(VELOX_GLOG_VERSION\s+"?([^)"\s]+)"?\)'),
        ("G_RE2_VERSION", CMAKE_MODULES + "/re2.cmake",
         r'set\(VELOX_RE2_VERSION\s+"?([^)"\s]+)"?\)'),
        ("G_XSIMD_VERSION", CMAKE_MODULES + "/xsimd.cmake",
         r'set\(VELOX_XSIMD_VERSION\s+"?([^)"\s]+)"?\)'),
    )

    def __init__(self) -> None:
        if not self.DEPS_YAML.is_file():
            die("file not found: " + str(self.DEPS_YAML))
        git_url, self.presto_pin = presto_pin()
        self.sha, self.repo = self._resolve(presto_clone(git_url, self.presto_pin))

    def _resolve(self, presto_repo: Path) -> Tuple[str, Path]:
        """Return the velox submodule commit and a local clone containing it."""
        pin = self.presto_pin
        # `git ls-tree` reads the submodule pin without the submodule being initialized.
        ls_tree = git_or_die(presto_repo, "ls-tree", pin, self.SUBMODULE)
        if not ls_tree:
            die(f"submodule {self.SUBMODULE} not found in presto@{pin[:9]}")
        sha = ls_tree.split()[2]
        # Clone the submodule's upstream, taken from Presto's own .gitmodules.
        gitmodules = git_show(presto_repo, pin, ".gitmodules")
        match = re.search(
            rf'\[submodule "{re.escape(self.SUBMODULE)}"\][^\[]*?url\s*=\s*(\S+)', gitmodules
        )
        if not match:
            die(f"no url for submodule {self.SUBMODULE} in presto@{pin[:9]} .gitmodules")
        return sha, shallow_repo(BUILD_DIR / "velox-src", match.group(1), sha)

    def check(self, report: Reporter) -> None:
        """Check deps.yaml's G_*_VERSION pins against the resolved Velox tree."""
        sha = self.sha
        deps_yaml = self.DEPS_YAML.read_text()
        report.header(f"Velox (velox@{sha[:12]}, {self.SUBMODULE} submodule)")
        for deps_var, rel_path, pattern in self.PINS:
            match = re.search(pattern, git_show(self.repo, sha, rel_path))
            if not match:
                die(f"could not extract a version for {deps_var} from velox@{sha[:9]}"
                    f" {rel_path}; update Velox.PINS")
            ours = yaml_var(deps_yaml, deps_var, self.DEPS_YAML)
            theirs = match.group(1)
            # deps.yaml and Velox differ in "v" tag-prefix style, so compare without it;
            # suggestions keep the style deps.yaml already uses.
            if strip_v(ours) == strip_v(theirs):
                report.ok(f"{deps_var}: {ours}")
            else:
                suggested = ("v" if ours.startswith("v") else "") + strip_v(theirs)
                report.fail(f"{deps_var}: deps.yaml pins {ours} but velox@{sha[:9]} (used"
                            f" by presto@{self.presto_pin[:9]}) resolves {theirs}"
                            f" ({rel_path})",
                            f"set {deps_var} to {suggested} in"
                            " taskfiles/velox-connector/deps.yaml.")


# ── Entry point ───────────────────────────────────────────────────────────────


def main() -> None:
    _, pin = presto_pin()
    report = Reporter()
    Presto().check(report)
    Velox().check(report)

    if report.failures:
        die(f"{report.failures} of {report.checks} dependency pins out of sync with"
            f" presto@{pin}. Update the files above to match the suggested versions.")
    print(f"All {report.checks} dependency pins are in sync with presto@{pin[:12]}.")


if __name__ == "__main__":
    main()
