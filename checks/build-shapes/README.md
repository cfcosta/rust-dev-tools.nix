# Cargo package-shape acceptance checks

Import the checks alongside the other flake checks:

```nix
// import ./checks/build-shapes { inherit pkgs self; }
```

The module returns `testLibraryBinaryShape` and `testWorkspaceBuildScriptShape`. It uses only the public `setup` and `buildRustPackage` interface, the diagnostic dependency derivation, and Cargo's public JSON build output. It does not import a backend library or inspect an artifact archive format.

Each check builds two stable-named source variants with identical manifests and lockfiles. It requires the dependency-artifact derivation to stay unchanged, the final derivation to change, and the installed executable to reflect the real edited sources. The final build must report the external registry dependency `cfg-if` as fresh. Local workspace crates are not required to be fresh; they contain the application code that must be rebuilt.

The fixtures cover:

- A package with both a library and a binary. The binary calls the library, so installing dummy library code cannot pass.
- A virtual workspace with an application, a path-dependent support library, and a local procedural macro.
- A real `build.rs` that invokes a native tool, reads the configured environment, and generates Rust code included by the application library.

The workspace source variants change the application library, support library, procedural macro, and build script. The expected executable output names all four changes. Stale generated code or a stale local dependency therefore fails the check even if compilation succeeds.

Run the checks before flake wiring with:

```sh
export RDT_ROOT="$PWD"
nix build --impure --no-link --print-out-paths --expr '
  let
    root = builtins.getEnv "RDT_ROOT";
    self = builtins.getFlake root;
    pkgs = import self.inputs.nixpkgs { system = builtins.currentSystem; };
  in builtins.attrValues (import (root + "/checks/build-shapes") {
    inherit pkgs self;
  })'
```

Extra Nix options such as `--option impure-env ''` can be added for hosts that inject incompatible fetcher variables. The checks do not alter host configuration.

These fixtures are an acceptance baseline, not a claim of support for every Cargo project layout. They do not cover out-of-tree path dependencies, custom target directories, examples, benchmarks, renamed target paths, or cross-compilation. An implementation that cannot handle a fixture shape must reject it explicitly rather than installing dummy code or silently omitting targets.
