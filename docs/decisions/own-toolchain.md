# 3. Build Rust toolchains from the official release manifests

Date: 2026-11-18

Status: Accepted

## Context

The toolchain came from rust-overlay's `pkgs.rust-bin`, which made the overlay a required input for this flake and for every consumer. With the package builder already in this repository, rust-overlay was the only dependency besides Nixpkgs.

Nixpkgs alone ships one Rust release, without nightly or a choice of version. The `rust` option promises any stable release, beta, nightly, a toolchain file, or a `rust-version`.

The `fromToolchainFile` and `fromCargoToml` selections were accepted but ignored: `setup` read only `channel` and `version`, which they do not set. The toolchain checks passed their selection as `version`, an option `setup` does not read, so each one built the default toolchain.

## Decision

Build toolchains in `rust-toolchain/default.nix` from the manifests Rust publishes on static.rust-lang.org. Keep Nixpkgs as the only flake input and remove the exported overlay.

Each release manifest lists every component's URL and sha256 for every target. Rust publishes a `.sha256` file beside each dated manifest. `rust-toolchain/manifests.json` therefore stores one hash per release: stable versions with their dates, and beta and nightly hashes by date. `scripts/update-rust-manifests.sh` adds the releases the index lacks and never rewrites an entry, because dated manifests do not change.

Evaluation fetches the selected manifest with `builtins.fetchurl` and its stored hash, then parses it with `fromTOML`. The manifest is about 900 KB and parses in a fraction of a second. This needs no import from derivation. Components are ordinary `fetchurl` derivations. Their contents merge into one sysroot, which `autoPatchelfHook` makes runnable on Linux.

`rustc`, `cargo`, and the host `rust-std` are required. `clippy`, `rustfmt`, `rust-analyzer`, and `rust-src` are added when the release ships them, unless the profile is `minimal`. Components and targets a caller requests must exist, otherwise evaluation fails. The manifest's `renames` table maps names such as `clippy` to `clippy-preview`.

## Boundaries

Rust's servers own toolchain contents and component hashes; the index only pins which manifest to trust. Nixpkgs owns fetching, patching, and the C toolchain used as linker.

The index covers each stable release from 1.8.0, the first with a version 2 manifest, except 1.14.0, whose rewritten manifest has no date. It covers each beta and nightly from 2025-01-01, and `--since` backfills earlier dates.

## Alternatives rejected

Nixpkgs' own `rustc` and `cargo` would need no index, but they drop version selection, nightly, and toolchain files.

Vendoring every component hash, as rust-overlay does, grows the index by megabytes each year. The release manifest already carries those hashes behind a single pinned hash.

Requiring callers to pass a manifest hash for any non-default toolchain makes the common pinned-version case awkward.

## Consequences

The first evaluation of a toolchain downloads its manifest once; Nix caches it by hash. Pure evaluation keeps working, because every fetch is pinned.

A release newer than the index fails with an instruction to run the update script. Darwin skips ELF patching and is untested here.

## Verification

`checks/toolchains` evaluates rejected selections: an unknown release, an unindexed nightly date, an unknown channel, and a missing component. It builds the latest stable and nightly, a pinned patch, a minor version resolving to its newest patch, a dated nightly, a `rust-version`, a legacy toolchain file, and a minimal-profile toolchain file with an extra component and a wasm target. Each check compares `rustc --version` and compiles a program. The package and cache checks build with the default toolchain and with toolchain-file, stable, and nightly selections.
