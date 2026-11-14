"""Copy this workspace's installable build artifacts before tests can alter them."""

import json
import pathlib
import shutil
import sys

metadata = json.load(open(sys.argv[1]))
members = set(metadata["workspace_members"])
out = pathlib.Path(sys.argv[3])
out.mkdir(parents=True, exist_ok=True)
seen = {}
for line in open(sys.argv[2]):
    artifact = json.loads(line)
    if artifact.get("reason") != "compiler-artifact" or artifact["package_id"] not in members:
        continue
    files = []
    if artifact.get("executable"):
        files.append(("bin", artifact["executable"]))
    if any(kind in ("cdylib", "staticlib", "dylib") for kind in artifact["target"]["crate_types"]):
        files.extend(("lib", f) for f in artifact["filenames"] if not f.endswith((".rlib", ".rmeta", ".d")))
    for directory, filename in files:
        source = pathlib.Path(filename)
        destination = out / directory / source.name
        if destination in seen and seen[destination] != source:
            raise ValueError(f"workspace artifacts collide at {destination}: {seen[destination]} and {source}")
        seen[destination] = source
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)
