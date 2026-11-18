{ pkgs, self }:
let
  rdt = self.setup pkgs { name = "rdt-layers"; };
  # smallvec, compiled for another package with other vendored crates.
  base = rdt.buildRustPackage { src = ../runtime-closure/fixture; };
  build =
    dependencyLayers:
    rdt.buildRustPackage {
      src = ./consumer;
      inherit dependencyLayers;
      postInstall = ''
        mkdir -p "$out/share"
        cp "$cargoBuildLog" "$out/share/cargo-build.json"
      '';
    };
  layered = build [ base.cargoArtifacts ];
  alone = build [ ];
  # The files a dependency stage stored, named by its layer count.
  listing =
    package:
    "zstd -dc ${package.cargoArtifacts}/target.tar.zst | tar -t > ${package.pname}-${toString (builtins.length package.cargoArtifacts.passthru.layers)}";
in
{
  testDependencyLayers =
    pkgs.runCommand "test-dependency-layers" { nativeBuildInputs = [ pkgs.zstd ]; }
      ''
        test ${builtins.head base.passthru.buildOnly} != ${builtins.head layered.passthru.buildOnly}
        test "$(${layered}/bin/rdt-layer-consumer)" = 4
        ${listing alone}
        ${listing layered}
        # Built alone, the dependency stage compiles both crates.
        grep -q '/build/smallvec/' rdt-layer-consumer-0
        grep -q '/build/itoa/' rdt-layer-consumer-0
        # Layered, it compiles only the crate the base lacks.
        if grep '/build/smallvec/' rdt-layer-consumer-1; then
          echo "smallvec was compiled again" >&2
          exit 1
        fi
        grep -q '/build/itoa/' rdt-layer-consumer-1
        # The final stage finds every dependency fresh.
        ${pkgs.jq}/bin/jq -e -s '
          [.[] | select(.reason == "compiler-artifact" and (.package_id | test("smallvec|itoa")))]
          | length == 2 and all(.fresh)
        ' ${layered}/share/cargo-build.json
        touch "$out"
      '';
}
