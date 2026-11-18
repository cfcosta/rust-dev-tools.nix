"""Turn Cargo unit graphs into the compiled crates a build can take ready-made.

Usage: plan-units.py GRAPH.json...

Each graph is the output of `cargo build --unit-graph` (or `cargo test
--no-run --unit-graph`) for one selection. The result lists one node per
registry crate as the build compiles it: its package, whether it is built
for the host, its resolved features, and the nodes it needs. A crate's build
script units belong to its node. Packages from the workspace, paths, or git
are not nodes, and neither is any crate that needs one.
"""

import json
import re
import sys

CACHEABLE_SOURCES = ("registry+", "sparse+")


def parse_package(pkg_id):
    # `registry+URL#name@version`, or the older `name version (source)`.
    match = re.fullmatch(r"(.+?)#(?:([^@]+)@)?(.+)", pkg_id)
    if match:
        source, name, version = match.groups()
        if name is None:
            # `path+file:///…/name#version`: the name is the path's last part.
            name = source.rstrip("/").rsplit("/", 1)[-1]
        return name, version, source
    match = re.fullmatch(r"(\S+) (\S+) \((.+)\)", pkg_id)
    if match:
        name, version, source = match.groups()
        return name, version, source
    raise ValueError(f"unrecognised package id: {pkg_id}")


def is_build_script(unit):
    return "custom-build" in unit["target"]["kind"]


def plan(graphs):
    """Nodes keyed like Cargo's units: a crate built with other dependencies
    is another node, even with the same features."""
    nodes = {}

    for graph in graphs:
        units = graph["units"]
        keys = {}

        def needs(index):
            """The library units a crate's own units (build script, its run) need."""
            unit = units[index]
            found = set()
            seen = set()
            stack = [dep["index"] for dep in unit["dependencies"]]
            while stack:
                current = stack.pop()
                if current in seen:
                    continue
                seen.add(current)
                dep = units[current]
                if dep["pkg_id"] == unit["pkg_id"] and (dep["mode"] == "run-custom-build" or is_build_script(dep)):
                    stack.extend(d["index"] for d in dep["dependencies"])
                elif dep["mode"] == "build" and not is_build_script(dep):
                    found.add(current)
            return found

        def key(index):
            if index in keys:
                return keys[index]
            unit = units[index]
            name, version, source = parse_package(unit["pkg_id"])
            deps = tuple(sorted(key(dep) for dep in needs(index)))
            result = (name, version, source, unit["platform"] is None, tuple(sorted(unit["features"])), deps)
            keys[index] = result
            nodes[result] = source.startswith(CACHEABLE_SOURCES) and all(nodes[dep] for dep in deps)
            return result

        for index, unit in enumerate(units):
            if unit["mode"] == "build" and not is_build_script(unit):
                key(index)

    kept = sorted(node for node, cacheable in nodes.items() if cacheable)
    position = {node: index for index, node in enumerate(kept)}
    return [
        {
            "name": name,
            "version": version,
            "source": source,
            "host": host,
            "features": list(features),
            "deps": sorted(position[dep] for dep in deps),
        }
        for (name, version, source, host, features, deps) in kept
    ]


if __name__ == "__main__":
    sys.setrecursionlimit(100000)
    graphs = [json.load(open(path)) for path in sys.argv[1:]]
    json.dump(plan(graphs), sys.stdout, indent=1, sort_keys=True)
    sys.stdout.write("\n")
