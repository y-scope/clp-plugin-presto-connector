#!/usr/bin/env python3
"""
Pins a chart's image references to the digests their tags currently resolve to.

Rewrites every `image.<component>` block in a values file that has a `tag` and an empty
`digest`, so that the packaged chart names the exact builds that existed when it was
published. Run it on a copy of the chart just before `helm package`; the repository's own
values file keeps its tags and is never modified.
"""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

EXPECTED_ARGS = 2
DIGEST_FORMAT = "{{.Manifest.Digest}}"
COMPONENT_RE = re.compile(r"^  ([A-Za-z0-9_.-]+):\s*$")
FIELD_RE = re.compile(r"^    ([A-Za-z0-9_.-]+):[ \t]*(.*?)[ \t]*$")
DIGEST_RE = re.compile(r"^sha256:[0-9a-f]{64}$")

if len(sys.argv) != EXPECTED_ARGS:
    sys.exit(f"usage: {sys.argv[0]} VALUES_FILE")
values_path = Path(sys.argv[1])

lines = values_path.read_text(encoding="utf-8").splitlines(keepends=True)

# Walk the `image:` block, remembering where each component's `digest` value sits.
components: dict[str, dict] = {}
in_image_block = False
current = None
for index, line in enumerate(lines):
    if re.match(r"^image:\s*$", line):
        in_image_block = True
        current = None
        continue
    if in_image_block and not line.startswith((" ", "\n", "#")):
        in_image_block = False
        current = None
        continue
    if not in_image_block:
        continue
    if match := COMPONENT_RE.match(line):
        current = match.group(1)
        components[current] = {"digest_value": "", "digest_line": None}
        continue
    if current is None:
        continue
    if match := FIELD_RE.match(line):
        # Drop a trailing `# comment`, which the kubectl digest carries.
        value = match.group(2).split(" #")[0].strip().strip('"')
        name = match.group(1)
        if name in ("repository", "tag"):
            components[current][name] = value
        elif name == "digest":
            components[current]["digest_value"] = value
            components[current]["digest_line"] = index

# A tagged image without a `digest` field cannot be pinned, and silently leaving it on a
# moving tag would defeat the point, so treat it as an error rather than skipping it.
for name, component in components.items():
    if component.get("tag") and component["digest_line"] is None:
        sys.exit(f"image.{name} has a tag but no digest field to pin")
    if component["digest_value"] and not DIGEST_RE.fullmatch(component["digest_value"]):
        sys.exit(f"image.{name} has a malformed digest: {component['digest_value']}")

unpinned = [
    name
    for name, component in components.items()
    if component.get("tag") and not component["digest_value"]
]

if not unpinned:
    sys.stderr.write("No image tags to pin.\n")
    sys.exit(0)

for name in unpinned:
    component = components[name]
    if not component.get("repository"):
        sys.exit(f"image.{name} has a tag but no repository")
    ref = f"{component['repository']}:{component['tag']}"
    try:
        result = subprocess.run(
            ["docker", "buildx", "imagetools", "inspect", "--format", DIGEST_FORMAT, ref],  # noqa: S607
            capture_output=True,
            text=True,
            check=False,
        )
    except FileNotFoundError:
        sys.exit("docker is not on PATH; resolving an image tag needs Docker with buildx")
    digest = result.stdout.strip()
    if result.returncode != 0 or not DIGEST_RE.fullmatch(digest):
        sys.exit(f"could not resolve {ref} to a digest: {result.stderr.strip()}")
    lines[component["digest_line"]] = f'    digest: "{digest}"\n'
    sys.stderr.write(f"{ref} -> {digest}\n")

values_path.write_text("".join(lines), encoding="utf-8")
