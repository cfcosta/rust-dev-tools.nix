{ pkgs, self }:
let
  inherit (pkgs) lib;
  source =
    variant:
    builtins.path {
      path = ./fixtures/cache + "/${variant}";
      name = "rdt-cache-source";
    };

  configuredTool = pkgs.writeShellScriptBin "rdt-configured-tool" ''
    printf configured
  '';
  callerTool = pkgs.writeShellScriptBin "rdt-caller-tool" ''
    printf caller
  '';
  nativeTool = pkgs.writeShellScriptBin "rdt-native-tool" ''
    printf native
  '';
  rustcWrapper = pkgs.writeShellScript "rdt-cache-rustc-wrapper" ''
    set -eu
    test "$RDT_SETUP_VALUE" = setup
    test "$RDT_CALLER_VALUE" = caller
    test "$RDT_PRECEDENCE" = caller
    test "$(rdt-configured-tool)" = configured
    test "$(rdt-caller-tool)" = caller
    test "$(rdt-native-tool)" = native
    exec "$@"
  '';

  setupArgs = {
    name = "rdt-cache-probe";
    dependencies = [ configuredTool ];
    env = {
      RDT_SETUP_VALUE = "setup";
      RDT_PRECEDENCE = "setup";
      RUSTC_WRAPPER = rustcWrapper;
    };
  };
  rdt = self.setup pkgs setupArgs;
  args = {
    src = source "before";
    cargoLock.lockFile = ./fixtures/cache/before/Cargo.lock;
    buildInputs = [ callerTool ];
    nativeBuildInputs = [
      nativeTool
      pkgs.jq
    ];
    env = {
      RDT_CALLER_VALUE = "caller";
      RDT_PRECEDENCE = "caller";
    };
    # This only runs in the real-source build. Requiring its Cargo JSON log
    # also catches accidental execution in the dependency-only derivation.
    postInstall = ''
      jq -es '
        [.[] | select(.reason == "compiler-artifact")]
        | ([.[] | select(.target.name == "cfg_if")] | length > 0 and all(.fresh))
          and ([.[] | select(.target.name == "rdt-cache-probe")] | length > 0 and all(.fresh == false))
      ' "$cargoBuildLog" >/dev/null || {
        echo 'Expected cached cfg-if artifacts and a newly compiled application' >&2
        jq -c 'select(.reason == "compiler-artifact") | {name: .target.name, fresh}' "$cargoBuildLog" >&2
        exit 1
      }
      mkdir -p "$out/share/rdt-cache-probe"
      cp "$cargoBuildLog" "$out/share/rdt-cache-probe/cargo-build.json"
      printf final-only > "$out/share/rdt-cache-probe/post-install"
    '';
  };
  build = extra: rdt.buildRustPackage (args // extra);
  before = build { };
  after = build { src = source "after"; };

  changedLock = pkgs.writeText "Cargo.lock" (
    builtins.readFile ./fixtures/cache/before/Cargo.lock + "\n# dependency-lock input changed\n"
  );
  otherToolchain = self.setup pkgs (
    setupArgs // { rust = self.version.fromToolchain "stable" "1.80.0"; }
  );
in
{
  inherit before after;
  variants = {
    feature = build { buildFeatures = [ "extra" ]; };
    profile = build { buildType = "debug"; };
    flags = build {
      env = args.env // {
        RUSTFLAGS = "-C opt-level=1";
      };
    };
    nativeInput = build { nativeBuildInputs = args.nativeBuildInputs ++ [ pkgs.gnumake ]; };
    toolchain = otherToolchain.buildRustPackage args;
    lockfile = build { cargoLock.lockFile = changedLock; };
  };
  invalid = {
    unknownOption = build { cargoHash = lib.fakeHash; };
    differentCheckType = build { checkType = "debug"; };
    differentCheckFeatures = build { checkFeatures = [ "extra" ]; };
    differentCheckDefaultFeatures = build { checkNoDefaultFeatures = true; };
    missingLockFile = build { cargoLock.outputHashes = { }; };
    unknownLockField = build {
      cargoLock = {
        lockFile = ./fixtures/cache/before/Cargo.lock;
        typo = true;
      };
    };
    reservedProfile = build {
      env = args.env // {
        CARGO_PROFILE = "dev";
      };
    };
    reservedSetupProfile =
      (self.setup pkgs (
        setupArgs
        // {
          env = setupArgs.env // {
            CARGO_PROFILE = "dev";
          };
        }
      )).buildRustPackage
        args;
    reservedArtifacts = build { passthru.cargoArtifacts = before.cargoArtifacts; };
  };
}
