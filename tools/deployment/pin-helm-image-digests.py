#!/usr/bin/env python3
"""Pins a chart's image references to the digests their tags currently resolve to.

Rewrites every `image.<component>` block in a values file that has a `tag` and an empty
`digest`, so that the packaged chart names the exact builds that existed when it was
published. Run it on a copy of the chart just before `helm package`; the repository's own
values file keeps its tags and is never modified.
"""

from __future__ import annotations

import re
import subprocess
import sys

COMPONENT_RE = re.compile(r"^  ([A-Za-z0-9]+):\s*$")
FIELD_RE = re.compile(r"^    ([A-Za-z0-9]+):[ \t]*(.*?)[ \t]*$")

if len(sys.argv) != 2:
    sys.exit(f"usage: {sys.argv[0]} VALUES_FILE")
path = sys.argv[1]

with open(path, encoding="utf-8") as values_file:
    lines = values_file.readlines()

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
        name, value = match.group(1), match.group(2).strip('"')
        if name in ("repository", "tag"):
            components[current][name] = value
        elif name == "digest":
            components[current]["digest_value"] = value
            components[current]["digest_line"] = index

unpinned = [
    name
    for name, component in components.items()
    if component.get("tag") and not component["digest_value"]
]

if not unpinned:
    print("No image tags to pin.", file=sys.stderr)
    sys.exit(0)

for name in unpinned:
    component = components[name]
    if not component.get("repository"):
        sys.exit(f"image.{name} has a tag but no repository")
    if component["digest_line"] is None:
        sys.exit(f"image.{name} has no digest field to pin")
    ref = f"{component['repository']}:{component['tag']}"
    result = subprocess.run(
        ["docker", "buildx", "imagetools", "inspect", "--format", "{{.Manifest.Digest}}", ref],
        capture_output=True,
        text=True,
    )
    digest = result.stdout.strip()
    if result.returncode != 0 or not re.fullmatch(r"sha256:[0-9a-f]{64}", digest):
        sys.exit(f"could not resolve {ref} to a digest: {result.stderr.strip()}")
    lines[component["digest_line"]] = f'    digest: "{digest}"\n'
    print(f"{ref} -> {digest}", file=sys.stderr)

with open(path, "w", encoding="utf-8") as values_file:
    values_file.writelines(lines)
