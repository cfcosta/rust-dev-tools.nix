# rust-dev-tools.nix

Rust toolchains, development commands, and Nix package builds for Rust projects. The package builder compiles dependencies in a separate derivation and reuses them after application-only edits. Nixpkgs is the only input: the toolchains come from Rust's official release manifests and the Cargo build stages live in this repository.

## Build a project

For a Cargo project with a checked-in `Cargo.lock`, add this `flake.nix`:

```nix
{
  inputs = {
    rust-dev-tools.url = "github:cfcosta/rust-dev-tools.nix";
    nixpkgs.follows = "rust-dev-tools/nixpkgs";
  };

  outputs = { nixpkgs, rust-dev-tools, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      rdt = rust-dev-tools.setup pkgs {
        name = "my-app";
        dependencies = [ pkgs.openssl ];
      };
    in
    {
      packages.${system}.default = rdt.buildRustPackage {
        src = ./.;
        cargoLock.lockFile = ./Cargo.lock;
      };
      devShells.${system}.default = pkgs.mkShell {
        packages = rdt.shellInputs;
      };
    };
}
```

Set `system` to your build platform. Remove OpenSSL if your project does not need it. No overlay is needed.

Run the package build:

```sh
nix build
```

The installed Cargo binaries appear in `result/bin`. The setup `name` controls development command names and the default derivation name; it does not rename your Cargo binaries.

Enter the development shell, then run the generated commands:

```sh
nix develop
my-app build
my-app check
my-app fmt
my-app test
```

`check` runs Clippy for tests and benchmarks. `test` runs cargo-nextest. The development commands use the same selected Rust toolchain as the package builder, but run in your working tree rather than the Nix package build.

## Configure the toolchain and build

`setup` defaults to the newest stable release in this repository's manifest index. To select another channel or release, set its `rust` option:

```nix
rdt = rust-dev-tools.setup pkgs {
  name = "my-app";
  rust = rust-dev-tools.version.fromToolchain "stable" "1.85.0";
  dependencies = [ pkgs.openssl ];
  env.OPENSSL_NO_VENDOR = "1";
};
```

The `rust` option takes one of these selections:

| Selection | Toolchain |
|---|---|
| `version.stable`, `version.nightly` | The newest indexed stable release or nightly. |
| `version.fromToolchain "stable" "1.85.0"` | That release. `"1.85"` takes the newest 1.85 patch, `"latest"` the newest release. |
| `version.fromToolchain "nightly" "2025-06-01"` | The nightly or beta of that date, or `"latest"`. |
| `version.fromToolchainFile ./rust-toolchain.toml` | The file's `channel`, `components`, `targets`, and `profile`. A legacy `rust-toolchain` file holding only a channel also works. |
| `version.fromCargoToml ./Cargo.toml` | The newest patch of the package or workspace `rust-version`. |

Every toolchain has `rustc`, `cargo`, and the host's `rust-std`. Unless the profile is `minimal`, it also has `clippy`, `rustfmt`, `rust-analyzer`, and `rust-src` when the release ships them. Add components or targets with `rust = version.fromToolchain "stable" "1.85.0" // { components = [ "llvm-tools" ]; targets = [ "wasm32-unknown-unknown" ]; };`. A requested component the release lacks fails during evaluation.

To build with stable but format with a nightly's unstable rustfmt options, give `rustfmt` a second selection: `rust = version.fromToolchainFile ./rust-toolchain.toml // { rustfmt = version.fromToolchain "nightly" "2026-11-18"; };`. The toolchain then has that nightly's `rustfmt` and `cargo-fmt`, and the rest is the stable release.

The index in `rust-toolchain/manifests.json` holds one sha256 per dated release manifest: every stable release from 1.8.0 except 1.14.0, whose manifest has no date, and each beta and nightly from 2025-01-01. Evaluation fetches the selected manifest, and the components are fixed-output fetches of the URLs and hashes it lists. A daily workflow (`.github/workflows/flake.yml`) runs `scripts/update-rust-manifests.sh` and commits new releases. Run it yourself to add releases sooner, or `scripts/update-rust-manifests.sh --since YYYY-MM-DD` to also index older betas and nightlies. See [the toolchain decision](docs/decisions/own-toolchain.md).

Configure features, profile, native tools, and final installation through the package call:

```nix
rdt.buildRustPackage {
  src = ./.;
  buildType = "release";
  buildNoDefaultFeatures = true;
  buildFeatures = [ "tls" ];
  nativeBuildInputs = [ pkgs.protobuf ];
  env.RUST_LOG = "info";
  postInstall = ''
    install -Dm644 assets/my-app.conf $out/share/my-app/my-app.conf
  '';
}
```

Use features and paths that exist in your project. Both compilation stages receive the same profile, features, native inputs, and environment. `postInstall` runs only for the final package.

## Supported package arguments

This is a supported subset of the Nixpkgs builder interface, not a drop-in replacement for every `rustPlatform.buildRustPackage` option. Unknown arguments fail during evaluation.

| Argument | Meaning |
|---|---|
| `src` | Required Cargo project source. |
| `name` | Final derivation name; defaults to the setup `name`. |
| `pname`, `version` | Optional package identity overrides. The builder reads omitted values from the root manifest. Supply them when the root is a workspace without package identity. |
| `cargoLock` | Omit to discover `src/Cargo.lock`, or set `{ lockFile = ./Cargo.lock; outputHashes = { }; }`. These are the only accepted nested fields. |
| `buildInputs`, `nativeBuildInputs` | Additional inputs for both compilation stages. Configured dependencies and platform tools are included first. |
| `env` | Package environment overrides for both stages. |
| `buildType` | Cargo profile, default `"release"`. `"debug"` maps to Cargo's `"dev"` profile. |
| `buildFeatures`, `buildNoDefaultFeatures` | Feature list and default-feature toggle; defaults are `[ ]` and `false`. |
| `checkType`, `checkFeatures`, `checkNoDefaultFeatures` | Optional check settings. Each must equal its corresponding build setting. |
| `cargoPackages` | Workspace packages to build and install, as `--package` arguments to both stages; defaults to `[ ]`, Cargo's default selection. |
| `checkPackages` | Packages whose tests run; defaults to `cargoPackages`. |
| `doCheck` | Run package tests and prepare dev-dependencies; defaults to `true`. |
| `useNextest` | Run the tests with cargo-nextest instead of `cargo test`; defaults to `false`. |
| `nativeCheckInputs` | Tools the tests need, in the final stage only. |
| `postInstall` | Additional final-package installation commands. |
| `postFixup` | Final-package commands after fixup, such as `wrapProgram`. |
| `desktopItems` | Desktop entries for `copyDesktopItems`, which must be in `nativeBuildInputs`. |
| `doInstallCheck`, `installCheckPhase` | Checks against the installed package. |
| `meta`, `passthru` | Final-package metadata and caller passthru attributes. `passthru.cargoArtifacts` and `passthru.buildOnly` are reserved. |

For Git dependencies, place source hashes in `cargoLock.outputHashes`, keyed by `"crate-name-version"`. A supplied lockfile replaces `src/Cargo.lock` in both compilation stages. The builder reads its contents before removing source-path context, so `cargoLock.lockFile = "${src}/Cargo.lock"` does not make unrelated source edits invalidate dependencies. Changed lockfile contents still invalidate the dependency artifacts.

Environment precedence is generated defaults, then `setup`'s `env`, then the package `env`. Later values replace earlier ones, including compiler and target-linker overrides. An explicit `RUSTFLAGS` replaces the generated linker flags in both compilation stages. `CARGO_PROFILE` is reserved in user environment sets; select the profile with `buildType`. `CARGO_HOME` and `CARGO_TARGET_DIR` receive build-local defaults unless supplied in the shared environment.

The builder rejects hash-based vendoring options such as `cargoHash` and `cargoSha256`, vendor-directory overrides, raw Cargo flags, custom build and check phases, source hooks, patches, Nextest filters, auditing options, and sysroot controls. Preprocess source outside this builder if needed. There is no public `cargoArtifacts` input or separate dependency-stage options object.

`createRustPlatform` remains available as the existing lower-level toolchain platform export. It is not the cached package workflow described here.

## Cache behavior

An edit to an existing local Rust source file normally reuses compiled external dependencies. Local workspace and path crates are rebuilt from their real sources in the final stage. A dependency feature change, toolchain change, profile change, native-input change, or relevant Cargo configuration change can invalidate the dependency artifacts.

The dependency stage builds a stub project from manifests, Cargo configuration, and Rust-file names, without reading Rust source contents. The final stage restores the compiled target directory and builds the real sources. A different dummy build-script path forces Cargo to rebuild local crates and execute their real build scripts. Cargo JSON identifies the workspace binaries and native libraries to install.

The builder preserves Cargo fingerprints and lets Cargo decide whether each external artifact is fresh. It does not force reuse when compilation settings differ. Referencing the whole application source from an environment variable or another shared input can also make source edits invalidate dependencies.

Unrelated files included in `src` can still invalidate the final package. Filter your source when appropriate, without excluding files needed by build scripts or `include_str!`.

Both stages pass rustc `--remap-path-prefix` for the vendored crates and the toolchain, so the panic locations compiled into a binary do not keep either in its runtime closure; `package.buildOnly` lists the two paths. The dependency derivation is a build input only, so garbage collection removes it unless something roots the package's build.

The returned package exposes `package.cargoArtifacts` for inspecting the dependency derivation. It is diagnostic output, not an artifact override. Change compilation settings through `buildRustPackage` arguments rather than a later `overrideAttrs`, which is outside the shared-input guarantee.

See [the local caching decision](docs/decisions/local-cache.md) for the implementation choice and compatibility limits.

## Supported source layouts

`src` must be a directory with a root `Cargo.toml`. Omit `cargoLock` only when `src/Cargo.lock` exists. The builder supports packages with library and binary targets, virtual workspaces, in-tree path dependencies, procedural macros, local build scripts, explicit target paths, and named Cargo profiles. Supply explicit `pname` and `version` for a virtual workspace.

Local path dependencies must remain inside `src`. The source planner rejects symlinks in the supplied tree and local packages with a `links` declaration. A local `links` build script can provide metadata needed during dependency compilation, which a stub cannot safely supply.

The source planner skips `.git` and `target` directories, then parses every nested `Cargo.toml`, including unrelated fixtures and excluded workspace members. All retained manifests must be valid and satisfy the same local-package restrictions. Manifests, Cargo configuration, and the Rust-file inventory are conservative cache inputs, so adding an unused Rust file can invalidate dependencies.

Source planning and lockfile discovery read files during Nix evaluation. Derivation-produced sources or lockfiles therefore require import from derivation (IFD). The current verification covers native x86_64-linux builds. It does not establish Darwin or cross-compilation support.

## Check this repository

Run the flake checks and the focused cache regression:

```sh
nix flake check
bash scripts/verify-cache.sh
```

The cache regression exercises the exported builder with source variants and an external dependency. Cargo JSON must mark `cfg-if` fresh while the real application compiles, and the installed binaries must produce different outputs. Matching dependency derivation paths alone does not prove reuse.

On hosts that inject incompatible curl flags into Nix fetchers, run these commands with the command-local workaround:

```sh
nix flake check --option impure-env ''
bash scripts/verify-cache.sh --option impure-env ''
```

The workaround is not required by the builder and does not change host configuration.
