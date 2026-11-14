{ pkgs, self }:
let
  inherit (pkgs) lib;
  nativeTool = pkgs.writeShellScriptBin "rdt-shape-tool" ''
    printf native
  '';
  rdt = self.setup pkgs {
    name = "rdt-build-shapes";
    env.RDT_SHAPE_BUILD_VALUE = "configured";
  };
  source =
    shape: variant:
    builtins.path {
      path = ./fixtures + "/${shape}/${variant}";
      name = "rdt-${shape}-source";
    };
  build =
    shape: variant:
    rdt.buildRustPackage {
      src = source shape variant;
      pname = "rdt-${shape}-shape";
      version = "0.1.0";
      nativeBuildInputs = [
        nativeTool
        pkgs.jq
      ];
      # Cargo's public JSON output establishes reuse without relying on the
      # builder's artifact format or on local crates being compiled in one phase.
      postInstall = ''
        jq -es '
          [.[] | select(.reason == "compiler-artifact" and .target.name == "cfg_if")]
          | length > 0 and all(.fresh)
        ' "$cargoBuildLog" >/dev/null || {
          echo 'The external dependency must remain fresh in the final shape build' >&2
          jq -c 'select(.reason == "compiler-artifact") | {name: .target.name, fresh}' "$cargoBuildLog" >&2
          exit 1
        }
        mkdir -p "$out/share/rdt-build-shapes"
        cp "$cargoBuildLog" "$out/share/rdt-build-shapes/cargo-build.json"
      '';
    };
  checkPair =
    {
      shape,
      binary,
      beforeOutput,
      afterOutput,
    }:
    let
      before = build shape "before";
      after = build shape "after";
    in
    assert lib.assertMsg (
      before.cargoArtifacts.drvPath == after.cargoArtifacts.drvPath
    ) "local ${shape} Rust edits must preserve the external dependency artifact key";
    assert lib.assertMsg (
      before.drvPath != after.drvPath
    ) "local ${shape} Rust edits must change the final package";
    pkgs.runCommand "test-${shape}-build-shape" { } ''
      beforeResult="$(${before}/bin/${binary})"
      afterResult="$(${after}/bin/${binary})"
      printf 'before: %s\nafter: %s\n' "$beforeResult" "$afterResult"
      test "$beforeResult" = ${lib.escapeShellArg beforeOutput}
      test "$afterResult" = ${lib.escapeShellArg afterOutput}
      mkdir -p "$out"
      cp ${before}/share/rdt-build-shapes/cargo-build.json "$out/before.json"
      cp ${after}/share/rdt-build-shapes/cargo-build.json "$out/after.json"
    '';
in
{
  testLibraryBinaryShape = checkPair {
    shape = "library";
    binary = "rdt-shape-library";
    beforeOutput = "library-before";
    afterOutput = "library-after";
  };
  testWorkspaceBuildScriptShape = checkPair {
    shape = "workspace";
    binary = "rdt-workspace-app";
    beforeOutput = "app-before support-before generated-before macro-before";
    afterOutput = "app-after support-after generated-after macro-after";
  };
}
