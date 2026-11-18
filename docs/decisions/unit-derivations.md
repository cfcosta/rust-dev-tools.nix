# 4. Build each registry crate in a derivation of its own

Date: 2026-11-18

Status: Accepted

## Context

Each package compiled all its dependencies in one derivation. Two packages that need the same crate, built the same way, compiled it twice, and a lockfile change that touched one crate rebuilt every dependency.

Cargo keys a compiled unit by the crate, its features, its dependencies' keys, the profile, the target, the compiler, and RUSTFLAGS, and not by the workspace. A unit another workspace compiled is fresh in this one if the source path and the environment its build script recorded also match. Two things kept units from matching between rdt builds: RUSTFLAGS named each package's vendor store path, and the vendored crates sat at that path.

## Decision

Vendored crates sit at `/build/cargo-vendor-dir` in the Linux sandbox, so the remap flag and the source paths are the same in every build. `PKG_CONFIG_PATH` names one directory of the inputs' `.pc` files, `/build/rdt-pkg-config`, so build scripts that record it stay fresh.

A committed plan, `rust-units.json`, lists for each selection (packages, features, profile, target, tests) the registry crates Cargo compiles, from `cargo build --unit-graph` and `cargo test --no-run --unit-graph`. A crate is a node with its package, whether it builds for the host, its resolved features, and the nodes it needs; a node's identity includes its dependencies', as Cargo's key does. Its build-script units belong to it. `nix run .#plan` writes the plan; each entry stores a hash of the manifests, Cargo configuration, and lockfile it was made from.

Each node becomes a derivation (`rust-cache/units.nix`). Its source is a workspace whose package depends on the crate and every crate it needs, each pinned with `=version`, `default-features = false`, and its resolved features, so Cargo resolves each to the plan's features and computes the same keys. Its vendored crates and lockfile are the part of the package's lockfile those crates reach. It starts from its dependencies' derivations and stores only the files it adds.

The package's dependency stage starts from the planned derivations and compiles what they lack: the workspace's stubs, and crates from git or paths. It also receives the native inputs and environment the planned crates declared, which their build scripts recorded.

## Alternatives rejected

A shared crate enabling the union of every project's features would make more units match, but it changes what each project compiles and adds a dependency to projects that publish to crates.io. Identical inputs, not aligned ones, decide sharing.

Computing the unit graph during evaluation would need the crates fetched and Cargo run before evaluation finishes, and a builder for each evaluated system.

Reimplementing Cargo's compilation, as `buildRustCrate` does, would lose Cargo's own checks and the package's normal `cargo build` and `cargo test`.

## Consequences

A plan covers the system it was made on; a missing or stale entry falls back to one dependency derivation, with an evaluation warning. Cargo still checks each ready-made unit, so a wrong plan or a missing native input costs a rebuild, never a wrong artifact, except where a build script reads an input it does not record.

A planned crate's native inputs come from Nixpkgs' `defaultCrateOverrides` and the package's `crateOverrides`, not from the package's `buildInputs`. A crate that needs one it was not given fails its own derivation.

The unit graph needs `-Z unstable-options`; the planner allows it on a stable Cargo with `__CARGO_TEST_CHANNEL_OVERRIDE_DO_NOT_USE_THIS`.

## Verification

`checks/dependency-layers` builds a package from another's compiled smallvec with other vendored crates, and checks that its dependency stage stores only itoa and its final stage finds both fresh. `checks/unit-plan` plans two packages, checks that they share smallvec's derivation, that the consumer's own stages compile no planned crate, and that a plan of other manifests is not used.
