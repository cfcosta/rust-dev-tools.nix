# rust-dev-tools.nix

Rust toolchains, development commands, and Nix package builds for Rust projects. The package builder uses Crane to cache compiled dependencies separately from your application, while keeping the familiar `rdt.buildRustPackage { ...; }` call.

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
      pkgs = import nixpkgs {
        inherit system;
        overlays = [ rust-dev-tools.overlays.default ];
      };
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

Set `system` to your build platform. Remove OpenSSL if your project does not need it. The Rust overlay is required because `setup` selects its toolchain from `pkgs.rust-bin`.

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

`setup` defaults to the latest stable toolchain available in the locked Rust overlay. To select another channel or release, set its `rust` option:

```nix
rdt = rust-dev-tools.setup pkgs {
  name = "my-app";
  rust = rust-dev-tools.version.fromToolchain "stable" "1.85.0";
  dependencies = [ pkgs.openssl ];
  env.OPENSSL_NO_VENDOR = "1";
};
```

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
| `pname`, `version` | Optional package identity overrides. Crane reads omitted values from the root manifest. Supply them when the root is a workspace without package identity. |
| `cargoLock` | Omit to discover `src/Cargo.lock`, or set `{ lockFile = ./Cargo.lock; outputHashes = { }; }`. These are the only accepted nested fields. |
| `buildInputs`, `nativeBuildInputs` | Additional inputs for both compilation stages. Configured dependencies and platform tools are included first. |
| `env` | Package environment overrides for both stages. |
| `buildType` | Cargo profile, default `"release"`. `"debug"` maps to Cargo's `"dev"` profile. |
| `buildFeatures`, `buildNoDefaultFeatures` | Feature list and default-feature toggle; defaults are `[ ]` and `false`. |
| `checkType`, `checkFeatures`, `checkNoDefaultFeatures` | Optional check settings. Each must equal its corresponding build setting. |
| `doCheck` | Run package tests and prepare dev-dependencies; defaults to `true`. |
| `postInstall` | Additional final-package installation commands. |
| `meta`, `passthru` | Final-package metadata and caller passthru attributes. `passthru.cargoArtifacts` is reserved. |

For Git dependencies, place source hashes in `cargoLock.outputHashes`, keyed by `"crate-name-version"`. A supplied lockfile is a build input, not a replacement for maintaining the project's dependency lock.

Environment precedence is generated defaults, then `setup`'s `env`, then the package `env`. Later values replace earlier ones. An explicit `RUSTFLAGS` replaces the generated linker flags in both compilation stages. `CARGO_PROFILE` is reserved in user environment sets; select the profile with `buildType`.

The builder rejects hash-based vendoring options such as `cargoHash` and `cargoSha256`, vendor-directory overrides, raw Cargo flags, custom phases, source hooks, patches, Nextest selection, auditing options, and sysroot controls. Preprocess source outside this builder if needed. There is no public `cargoArtifacts` input or separate dependency-stage options object.

`createRustPlatform` remains available as the existing lower-level toolchain platform export. It is not the cached package workflow described here.

## Cache behavior

An edit to an existing local Rust source file normally reuses compiled external dependencies. Local workspace and path crates are rebuilt from their real sources in the final stage. A dependency feature change, toolchain change, profile change, native-input change, or relevant Cargo configuration change can invalidate the dependency artifacts.

Crane preserves Cargo fingerprints and lets Cargo decide whether each artifact is fresh. It does not force reuse when compilation settings differ. Referencing the whole application source from an environment variable or another shared input can also make source edits invalidate dependencies.

Unrelated files included in `src` can still invalidate the final package. Filter your source when appropriate, without excluding files needed by build scripts or `include_str!`.

The returned package exposes `package.cargoArtifacts` for inspecting the dependency derivation. It is diagnostic output, not an artifact override. Change compilation settings through `buildRustPackage` arguments rather than a later `overrideAttrs`, which is outside the shared-input guarantee.

See [the Crane caching decision](docs/decisions/crane-cache.md) for the implementation choice, compatibility limits, and pinned upstream sources.

## Check this repository

Run the flake checks and the focused cache regression:

```sh
nix flake check
bash scripts/verify-cache.sh
```

The cache regression exercises the exported builder with source variants and an external dependency. A passing result must establish both artifact reuse and the changed executable behavior, not just matching derivation paths.
