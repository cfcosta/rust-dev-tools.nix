{ pkgs, self }:
let
  source =
    value:
    pkgs.runCommand "rdt-workspace-source" { } ''
      cp -R ${./fixtures/local-workspace} "$out"
      chmod -R u+w "$out"
      printf '%s' ${pkgs.lib.escapeShellArg value} > "$out/library/value.txt"
    '';
  linkerKey = "CARGO_TARGET_${pkgs.stdenv.hostPlatform.rust.cargoEnvVarTarget}_LINKER";
  packageLinker = pkgs.writeShellScript "rdt-selected-linker" ''
    touch "$NIX_BUILD_TOP/rdt-selected-linker-used"
    exec ${pkgs.stdenv.cc}/bin/${pkgs.stdenv.cc.targetPrefix}cc "$@"
  '';
  rdt = self.setup pkgs {
    name = "rdt-workspace";
    env = {
      CARGO_TARGET_DIR = "target-from-setup";
      ${linkerKey} = "setup-linker-must-be-overridden";
    };
  };
  args = value: {
    src = source value;
    pname = "rdt-workspace";
    version = "0.1.0";
    buildType = "fast";
    nativeBuildInputs = [ pkgs.jq ];
    env = {
      CARGO_TARGET_DIR = "target-from-package";
      ${linkerKey} = packageLinker;
    };
    postInstall = ''
      test -e "$NIX_BUILD_TOP/rdt-selected-linker-used"
      test "$CARGO_TARGET_DIR" = target-from-package
      test -d target-from-package
      test ! -d target-from-setup
      jq -es '
        [.[] | select(.reason == "compiler-artifact" and .target.name == "cfg_if")]
        | length > 0 and all(.fresh)
      ' "$cargoBuildLog" >/dev/null || {
        echo 'The external dependency must remain fresh in the final workspace build' >&2
        jq -c 'select(.reason == "compiler-artifact") | {name: .target.name, fresh}' "$cargoBuildLog" >&2
        exit 1
      }
      mkdir -p "$out/share/rdt-workspace"
      cp "$cargoBuildLog" "$out/share/rdt-workspace/cargo-build.json"
    '';
  };
  package = value: rdt.buildRustPackage (args value);
  before = package "before";
  after = package "after";
  explicit =
    value:
    rdt.buildRustPackage (
      (args value)
      // {
        cargoLock.lockFile = "${source value}/Cargo.lock";
      }
    );
in
assert pkgs.lib.assertMsg (
  before.cargoArtifacts.drvPath == after.cargoArtifacts.drvPath
) "non-Rust build-script input edits must preserve dependency artifacts";
assert pkgs.lib.assertMsg (
  before.drvPath != after.drvPath
) "non-Rust build-script input edits must rebuild the final workspace";
assert pkgs.lib.assertMsg (
  before.cargoArtifacts.drvPath == (explicit "before").cargoArtifacts.drvPath
) "automatic and explicit lockfile discovery must produce the same dependency key";
assert pkgs.lib.assertMsg (
  (explicit "before").cargoArtifacts.drvPath == (explicit "after").cargoArtifacts.drvPath
) "explicit source-context lockfiles must ignore non-Rust build-script input edits";
pkgs.runCommand "test-local-cargo-lifecycle" { } ''
  test "$(${before}/bin/rdt-workspace-probe)" = 'before 42'
  test "$(${after}/bin/rdt-workspace-probe)" = 'after 42'
  test -f ${before}/lib/liblocal_library${pkgs.stdenv.hostPlatform.extensions.sharedLibrary}
  test -f ${after}/lib/liblocal_library${pkgs.stdenv.hostPlatform.extensions.sharedLibrary}
  mkdir -p "$out"
  cp ${before}/share/rdt-workspace/cargo-build.json "$out/before.json"
  cp ${after}/share/rdt-workspace/cargo-build.json "$out/after.json"
''
