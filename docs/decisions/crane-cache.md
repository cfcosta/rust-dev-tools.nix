# 1. Cache compiled dependencies behind the existing package call

Date: 2026-11-14

Status: Superseded by [2. Own the compiled dependency cache](local-cache.md)

This document records the earlier Crane-backed design. The current builder has no Crane dependency. The original decision remains below for historical context.

## Context

The previous `buildRustPackage` wrapper used Nixpkgs' Rust builder. That builder prepared dependency sources separately, but compiled them inside the application derivation. An application source edit therefore started another build without the previous compiled dependencies.

Crane provides a separate dependency-artifact derivation. Its argument vocabulary differs from Nixpkgs, so changing the backend while forwarding arbitrary arguments could silently ignore settings such as `buildFeatures` or `cargoHash`.

The existing `setup` result and repository examples expose `buildRustPackage`. Preserving that common call avoids requiring every consumer to rename the builder and change lockfile syntax.

## Decision

Keep `rdt.buildRustPackage` as the sole high-level package builder. Back it with a narrow adapter to Crane, using a closed argument signature. Preserve the common `src` and `cargoLock.lockFile` call. Reject unsupported arguments during evaluation instead of claiming full Nixpkgs compatibility.

Construct one shared argument set for `buildDepsOnly` and the final `buildPackage` call. It owns the configured Rust toolchain, profile, features, environment, and native inputs. Final-only fields such as `postInstall` do not affect dependency compilation. Callers do not supply a second set of stage options or override the generated artifacts.

Pin [Crane v0.20.3](https://github.com/ipetkov/crane/tree/efd36682371678e2b6da3f108fdb5c613b3ec598) at `efd36682371678e2b6da3f108fdb5c613b3ec598`. Its [minimum supported Nixpkgs version is 24.11](https://github.com/ipetkov/crane/blob/efd36682371678e2b6da3f108fdb5c613b3ec598/lib/default.nix#L14-L17), matching the existing pin. This avoids coupling the caching change to a Nixpkgs upgrade.

## How the cache is separated

Crane's [`buildDepsOnly`](https://github.com/ipetkov/crane/blob/efd36682371678e2b6da3f108fdb5c613b3ec598/lib/buildDepsOnly.nix#L31-L86) replaces local code with dummy sources while keeping dependency-relevant project inputs. It checks, builds, and compiles tests, then exports Cargo artifacts. The final [`buildPackage`](https://github.com/ipetkov/crane/blob/efd36682371678e2b6da3f108fdb5c613b3ec598/lib/buildPackage.nix#L35-L58) consumes those artifacts with the real project source.

This shares completed crate artifacts and Cargo fingerprints across derivations. It does not rely on rustc incremental compilation, which Crane [disables by default](https://github.com/ipetkov/crane/blob/efd36682371678e2b6da3f108fdb5c613b3ec598/lib/setupHooks/configureCargoCommonVarsHook.sh#L11-L19). Cargo still recompiles artifacts when their inputs differ.

## Alternatives rejected

| Alternative | Reason |
|---|---|
| Rename the public builder to Crane-native `buildPackage` | Clear upstream semantics, but requires every existing caller to migrate. The selected adapter preserves the common call without adding a second workflow. |
| Forward arbitrary Nixpkgs options to Crane | Similar-looking fields do not necessarily have equivalent behavior. Silent acceptance could build the wrong configuration. |
| Emulate the complete Nixpkgs builder API | Custom phases, patches, flag arrays, auditing, and sysroots would turn this feature into a separate compatibility framework. |
| Expose separate public dependency and final-build functions | Makes callers responsible for keeping both stages' compilation inputs consistent. |
| Add a backend switch | Leaves two package-building paths to maintain and does not make compiled dependency reuse the normal behavior. |

## Consequences

The common package call remains valid, but advanced usage is intentionally narrower. Hash-based vendoring, source hooks, patches, custom phases, raw Cargo flags, and distinct build/check compilation settings are unsupported. [The README lists the supported arguments](../../README.md#supported-package-arguments).

Environment merging is explicit: generated defaults, setup environment, then package environment. Caller `RUSTFLAGS` replaces generated flags in both stages. The adapter owns `CARGO_PROFILE`, so callers use `buildType` instead.

Changes to existing local Rust source contents can preserve dependency artifacts. Changes to manifests, features, Cargo configuration, toolchain, profile, or native inputs can invalidate them. Local workspace crates still rebuild in the final stage. Source-dependent values added to shared inputs can undo cache separation.

The existing lower-level `createRustPlatform` export remains unchanged. No old Nixpkgs backend, native-builder alias, or public manual artifact path is added.

## Verification contract

The repository's cache regression must exercise the exported `setup` builder and an external dependency. In-tree path crates alone cannot prove external dependency reuse because Crane replaces local code with stubs.

A passing check must show that a source-only edit preserves dependency-artifact identity, changes the application output, and leaves the external dependency fresh during final compilation. Relevant input changes must invalidate the dependency artifact derivation. Matching paths alone are not sufficient evidence of Cargo reuse.

The implementation also needs checks for unsupported arguments and consistent environment, profile, and native-input propagation. This document records the required behavior; it does not claim those checks have passed.
