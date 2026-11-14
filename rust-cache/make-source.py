"""Construct compilable local stubs from a content-only Cargo source plan."""

import json
import pathlib
import sys

import toml

plan = json.load(open(sys.argv[1]))
root = pathlib.Path(sys.argv[2])
root.mkdir(parents=True, exist_ok=True)


def inside(base, relative):
    path = pathlib.PurePosixPath(relative)
    if path.is_absolute():
        raise ValueError(f"absolute local Cargo path is unsupported: {relative}")
    parts = list(base.parts)
    for part in path.parts:
        if part == "..":
            if not parts:
                raise ValueError(f"Cargo path escapes src: {base}/{relative}")
            parts.pop()
        elif part != ".":
            parts.append(part)
    return pathlib.PurePosixPath(*parts)


def write(path, text):
    destination = root / str(path)
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(text)


def check_dependencies(base, dependencies):
    for dependency in dependencies.values():
        if isinstance(dependency, dict) and "path" in dependency:
            manifest = str(inside(base, dependency["path"]) / "Cargo.toml")
            if manifest not in plan["manifests"]:
                raise ValueError(f"local dependency manifest is outside supplied src: {manifest}")


# Keep the source layout so Cargo performs its own automatic target discovery.
# Library and proc-macro crates may contain a private unused main function.
for path in plan["rustFiles"]:
    write(path, "fn main() {}\n")
for path, contents in plan["configs"].items():
    write(path, contents)
for path, manifest in plan["manifests"].items():
    base = pathlib.PurePosixPath(path).parent
    for key in ("dependencies", "build-dependencies", "dev-dependencies"):
        check_dependencies(base, manifest.get(key, {}))
        for target in manifest.get("target", {}).values():
            check_dependencies(base, target.get(key, {}))
    check_dependencies(base, manifest.get("workspace", {}).get("dependencies", {}))
    for registry in manifest.get("patch", {}).values():
        check_dependencies(base, registry)
    check_dependencies(base, manifest.get("replace", {}))

    if "package" in manifest:
        package = manifest["package"]
        if "links" in package:
            raise ValueError(f"local links packages need real build-script metadata and are unsupported: {path}")
        # The changed manifest build-script path forces Cargo to invalidate all
        # local stub units when real sources replace them, even at epoch mtimes.
        package["build"] = ".rdt-cache-dependency/build.rs"
        marker = str(base / package["build"])
        if marker in plan["rustFiles"]:
            raise ValueError(f"source uses reserved dependency marker: {marker}")
        write(base / package["build"], "fn main() {}\n")
        for kind in ("bin", "example", "test", "bench"):
            for target in manifest.get(kind, []):
                if "path" in target:
                    write(inside(base, target["path"]), "fn main() {}\n")
        if "lib" in manifest and "path" in manifest["lib"]:
            write(inside(base, manifest["lib"]["path"]), "fn main() {}\n")
    write(path, toml.dumps(manifest))
