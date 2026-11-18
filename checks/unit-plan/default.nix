{ pkgs, self }:
let
  inherit (pkgs) lib;
  rdt = self.setup pkgs { name = "rdt-units"; };
  # Two packages whose committed plans both need smallvec 1.16.6, built the
  # same way; the consumer also needs itoa.
  base = rdt.buildRustPackage {
    src = ../runtime-closure/fixture;
    unitPlan = ./base.json;
  };
  consumer = rdt.buildRustPackage {
    src = ../dependency-layers/consumer;
    unitPlan = ./consumer.json;
    postInstall = ''
      mkdir -p "$out/share"
      cp "$cargoBuildLog" "$out/share/cargo-build.json"
    '';
  };
  # The consumer's plan read as the base's: made from other manifests.
  stale = rdt.buildRustPackage {
    src = ../dependency-layers/consumer;
    unitPlan = ./base.json;
  };
  units = package: map (unit: unit.drvPath) package.cargoArtifacts.passthru.layers;
  smallvec = package: lib.filter (path: lib.hasInfix "rust-unit-smallvec-" path) (units package);
in
assert lib.assertMsg (base.passthru.unitPlan.units == 1) "the base plans smallvec";
assert lib.assertMsg (consumer.passthru.unitPlan.units == 2) "the consumer plans smallvec and itoa";
assert lib.assertMsg (
  smallvec base == smallvec consumer && smallvec base != [ ]
) "both packages take smallvec from one derivation";
assert lib.assertMsg (stale.passthru.unitPlan.units == 0) "a plan of other manifests is not used";
{
  testUnitPlan = pkgs.runCommand "test-unit-plan" { nativeBuildInputs = [ pkgs.zstd ]; } ''
    test "$(${consumer}/bin/rdt-layer-consumer)" = 4
    # The consumer's own dependency stage compiles no registry crate.
    zstd -dc ${consumer.cargoArtifacts}/target.tar.zst | tar -t > stored
    if grep -E '/build/(smallvec|itoa)/' stored; then
      echo "a planned crate was compiled again" >&2
      exit 1
    fi
    # And its final stage finds both fresh.
    ${pkgs.jq}/bin/jq -e -s '
      [.[] | select(.reason == "compiler-artifact" and (.package_id | test("smallvec|itoa")))]
      | length == 2 and all(.fresh)
    ' ${consumer}/share/cargo-build.json
    touch "$out"
  '';
}
