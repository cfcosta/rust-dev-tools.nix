# 2. Own the compiled dependency cache behind the existing package call

Date: 2026-11-14

Status: Accepted

Supersedes [1. Cache compiled dependencies behind the existing package call](crane-cache.md).

## Context

The original Nixpkgs-backed builder cached dependency sources but compiled dependencies inside the application derivation. An application-only edit therefore started another dependency compilation.

The requested implementation belongs in this repository. The earlier Crane adapter did not meet that requirement. This implementation uses Cargo, Nixpkgs' lockfile importer, and ordinary stdenv tools. It neither depends on Crane nor vendors its implementation.

The existing `setup` result exposes `rdt.buildRustPackage`. Keeping that call avoids a consumer migration while allowing a narrow, explicit argument contract.

## Decision

Own the Cargo lifecycle in `build-rust-package.nix`. Construct the dependency and final derivations from one compilation record containing the configured toolchain, compiler environment, native inputs, features, and profile. Caller environment values override generated defaults in both stages. `CARGO_PROFILE` remains reserved so callers select the shared profile through `buildType`.

`rust-cache/source-plan.nix` reads all manifests, Cargo configuration, and the inventory of local Rust files. It does not read Rust source contents. `make-source.py` creates a stub tree with the same local target layout and a different build-script path for each package. When the real manifests return, that path difference forces Cargo to invalidate local stub units even when Nix normalizes source timestamps.

The dependency derivation compiles the stub project and, when `doCheck` is enabled, prepares test artifacts without running tests. It exports Cargo's target directory as a normalized archive. The final derivation restores the archive, compiles the real sources, runs tests, and installs workspace binaries and native libraries identified by Cargo JSON. It retains the final build log in `$cargoBuildLog` for installation hooks and verification.

Read an explicit lockfile before removing its source-path string context. Pass only its contents to the dependency derivation and Nixpkgs' `importCargoLock`, preserving `outputHashes` for Git sources. A path such as `"${src}/Cargo.lock"` therefore does not retain unrelated source contents in the dependency key. Both build stages use the supplied lockfile, and changed lock contents still invalidate dependency artifacts.

## Boundaries

Nixpkgs owns registry and Git source fetching through `importCargoLock`, including checksum verification and Git output hashes. This repository owns source planning, stub generation, dependency compilation, artifact export and restoration, the final Cargo commands, and installation.

The builder supports native Cargo packages with library and binary targets, virtual workspaces, in-tree path dependencies, procedural macros, local build scripts, explicit target paths, and named Cargo profiles. Cargo home and target directories receive build-local defaults. Explicit caller directory, compiler, and linker environment values take precedence over those defaults.

Local build scripts execute only in the real-source stage. Their generated files and non-Rust inputs need not appear in the stub tree. The changed build-script path ensures the real script executes after restoration. External dependencies remain reusable when their own compilation inputs match.

## Alternatives rejected

Using Crane would outsource the mechanism that the user asked this repository to implement. Copying its implementation into this tree would not meet that requirement either.

We also prototyped a cache layered over the pinned Nixpkgs `buildRustPackage` hooks. Both prototypes passed the core reuse and workspace checks. Runtime probes found that the hook-based prototype overwrote an explicit caller linker and failed to export artifacts when the caller set `CARGO_TARGET_DIR`. The direct Cargo lifecycle passed both probes and avoids those interactions between custom phases and Nixpkgs hooks. Following the prove-it-works principle, actual linker execution and completed builds decided the choice.

## Consequences

The repository now maintains Cargo environment setup and artifact installation. The public builder supports the [documented argument subset](../../README.md#supported-package-arguments), not every Nixpkgs option. It rejects unknown fields, separate build and check settings, raw Cargo flags, custom phases, source hooks, and manual artifact overrides.

The initial source planner is conservative. It skips `.git` and `target` directories, then parses every nested `Cargo.toml`, including unrelated fixtures and excluded workspace members. An invalid or unsupported unused manifest can therefore reject an otherwise valid workspace. It also rejects source symlinks, paths outside `src`, and local packages declaring `links`. A stub cannot safely provide the build-script metadata that a local `links` package may need during dependency compilation.

All retained manifests, Cargo configuration, and the Rust-file inventory participate in the dependency key. Metadata changes or adding an unused Rust file can cause an extra cache miss. Existing Rust file contents do not. Source-dependent environment values or other shared inputs can reintroduce a dependency on application sources.

Source planning and lockfile discovery read files during evaluation. Derivation-produced sources and lockfiles require import from derivation (IFD). This is a cost of constructing a content-based dependency key before the build.

The cache preserves completed crate artifacts and Cargo fingerprints. It disables rustc incremental compilation by default. Cargo still decides freshness, and toolchain, target, features, profile, flags, native inputs, and lock contents can invalidate artifacts.

## Verification

The permanent regression builds two application variants with the external registry dependency `cfg-if`. Cargo JSON must mark that dependency fresh and each real application newly compiled. Installed outputs must differ. A scratch negative control that skips artifact restoration fails the freshness assertion.

Workspace checks exercise local path libraries, procedural macros, custom target paths and profiles, caller linker and target-directory overrides, and build-script-generated code. Changing a non-Rust build-script input preserves dependency identity but changes the installed executable. Argument rejection and relevant-input invalidation checks run through the public `setup` interface.

Run `nix flake check` and `bash scripts/verify-cache.sh` for the permanent checks. The proven platform is native x86_64-linux. These checks do not establish Darwin or cross-compilation support. Existing foreign-system evaluation issues remain outside this change.
