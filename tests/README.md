# Package-builder cache regression checks

Run the checks through the public `setup` API:

```sh
scripts/verify-cache.sh
```

The script accepts extra Nix options. For example, use `--option impure-env ''` when a host injects incompatible fetcher environment variables. The script does not change host configuration.

`default.nix` returns four flake checks when imported with `{ pkgs, self }`:

- `testLocalLifecycle` exercises a workspace with path libraries, a proc macro, custom target paths, a custom profile, and a build script reading a changed non-Rust input. The custom profile enables debug assertions that the installed executable requires. The check requires the caller's linker and target-directory overrides to take precedence, installs a shared library, and checks automatic and explicit lockfile discovery. Changing only the build-script input keeps the dependency key and external `cfg-if` artifacts fresh while changing the executable output from `before 42` to `after 42`.
- `testCacheReuse` builds two applications differing only in their existing Rust source. Their dependency-artifact derivation is identical, their final derivations differ, and their installed binaries print different results. Each final build asserts from Cargo JSON that the external registry crate `cfg-if` is fresh and the application is compiled.
- `testCacheInvalidation` checks that features, profile, Rust flags, native inputs, configured toolchain, and lockfile inputs change the dependency-artifact derivation. These variants are evaluated, not all compiled.
- `testBuilderArguments` checks evaluation rejection for invalid supported-field values. The script additionally checks unknown top-level arguments in separate Nix processes, because Nix function-argument errors cannot be caught by `builtins.tryEval`.

A compiler wrapper requires configured and caller environment variables, environment precedence, configured dependencies, caller build inputs, and caller native tools whenever rustc runs. This exercises their availability during dependency compilation as well as final compilation. The final-only installation hook both inspects freshness and saves the Cargo JSON logs in the check output.

The tiny registry dependency is intentional. The local planner replaces in-tree path and workspace crates with dummy code, so recompilation of those crates would not establish an external dependency-cache miss. The fixtures have identical manifests and lockfiles and the same stable source name.

These are behavior checks, not timing benchmarks. They run native builds for the selected package set and do not prove cross-compilation support.
