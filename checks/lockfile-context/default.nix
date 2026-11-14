{ pkgs, self }:
let
  rdt = self.setup pkgs { name = "lock-context"; };
  source =
    variant:
    builtins.path {
      path = ./fixtures + "/${variant}";
      name = "source";
    };
  baseSrc = source "base";
  editedSrc = source "edited";
  package =
    src: lockFile:
    rdt.buildRustPackage {
      inherit src;
      cargoLock = {
        inherit lockFile;
        outputHashes = { };
      };
    };
  base = package baseSrc "${baseSrc}/Cargo.lock";
  edited = package editedSrc "${editedSrc}/Cargo.lock";
  changedLock = package baseSrc ./fixtures/changed.lock;
  generatedLock = pkgs.runCommand "lock-context-generated-lock" { } ''
    cp ${./fixtures/base/Cargo.lock} $out
  '';
  fromGeneratedLock = package baseSrc "${generatedLock}";
in
assert pkgs.lib.assertMsg (base.cargoArtifacts.drvPath == edited.cargoArtifacts.drvPath)
  "application-only source edits must preserve dependency artifacts with an explicit store-context lockfile";
assert pkgs.lib.assertMsg (
  base.drvPath != edited.drvPath
) "application-only source edits must change the final package derivation";
assert pkgs.lib.assertMsg (
  base.cargoArtifacts.drvPath != changedLock.cargoArtifacts.drvPath
) "changed explicit lockfile contents must invalidate dependency artifacts";
assert pkgs.lib.assertMsg (
  base.cargoArtifacts.drvPath == fromGeneratedLock.cargoArtifacts.drvPath
) "a derivation-produced explicit lockfile must be read before its source context is discarded";
pkgs.runCommand "test-lockfile-context" { } ''
  touch $out
''
