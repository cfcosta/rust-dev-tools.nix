{ pkgs, self }:
let
  inherit (pkgs) lib;
  packages = import ./packages.nix { inherit pkgs self; };
  inherit (packages) before after;
  artifactPath = package: package.cargoArtifacts.drvPath;
  changed = lib.mapAttrs (_: package: artifactPath package != artifactPath before) packages.variants;
  # Unexpected function arguments are evaluator errors, not catchable throws.
  # The companion script exercises that case in a separate Nix process.
  semanticErrors = builtins.removeAttrs packages.invalid [
    "unknownOption"
    "missingLockFile"
    "unknownLockField"
  ];
  rejected = lib.mapAttrs (_: package: !(builtins.tryEval package.drvPath).success) semanticErrors;
in
{
  testLocalLifecycle = import ./local-lifecycle.nix { inherit pkgs self; };

  testCacheReuse =
    assert lib.assertMsg (
      artifactPath before == artifactPath after
    ) "application-only changes must reuse the dependency artifact derivation";
    assert lib.assertMsg (
      before.drvPath != after.drvPath
    ) "application-only changes must rebuild the final package";
    pkgs.runCommand "test-compiled-dependency-reuse" { } ''
      test "$(${before}/bin/rdt-cache-probe)" = 'before default'
      test "$(${after}/bin/rdt-cache-probe)" = 'after default'
      test "$(cat ${before}/share/rdt-cache-probe/post-install)" = final-only
      test "$(cat ${after}/share/rdt-cache-probe/post-install)" = final-only
      mkdir -p "$out"
      cp ${before}/share/rdt-cache-probe/cargo-build.json "$out/before.json"
      cp ${after}/share/rdt-cache-probe/cargo-build.json "$out/after.json"
    '';

  testCacheInvalidation =
    assert lib.assertMsg (builtins.all (value: value) (builtins.attrValues changed))
      "features, profile, flags, native inputs, toolchain, and lockfile must invalidate dependency artifacts";
    pkgs.runCommand "test-dependency-cache-invalidation" { } ''
      mkdir -p "$out"
      printf '%s\n' ${lib.escapeShellArg (builtins.toJSON changed)} > "$out/cases.json"
    '';

  testBuilderArguments =
    assert lib.assertMsg (builtins.all (value: value) (
      builtins.attrValues rejected
    )) "invalid package arguments must fail during evaluation";
    pkgs.runCommand "test-package-builder-arguments" { } ''
      mkdir -p "$out"
      printf '%s\n' ${lib.escapeShellArg (builtins.toJSON rejected)} > "$out/cases.json"
    '';
}
