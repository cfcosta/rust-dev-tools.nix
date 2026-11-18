{
  pkgs,
  rust,
  defaults,
}:
{
  src,
  name ? defaults.name,
  pname ? null,
  version ? null,
  cargoLock ? null,
  buildInputs ? [ ],
  nativeBuildInputs ? [ ],
  env ? { },
  buildType ? "release",
  buildFeatures ? [ ],
  buildNoDefaultFeatures ? false,
  checkType ? buildType,
  checkFeatures ? buildFeatures,
  checkNoDefaultFeatures ? buildNoDefaultFeatures,
  doCheck ? true,
  postInstall ? "",
  meta ? { },
  passthru ? { },
}:
let
  inherit (pkgs) lib;
  mergedEnv = defaults.env // env;
  profile = if buildType == "debug" then "dev" else buildType;
  readContents = file: builtins.unsafeDiscardStringContext (builtins.readFile file);
  lockArgs =
    {
      lockFile,
      outputHashes ? { },
    }:
    {
      lockFileContents = readContents lockFile;
      inherit outputHashes;
    };
  lock =
    if cargoLock == null then
      {
        lockFileContents = readContents (toString src + "/Cargo.lock");
      }
    else
      lockArgs cargoLock;
  rustPlatform = pkgs.makeRustPlatform {
    cargo = rust;
    rustc = rust;
  };
  vendor = rustPlatform.importCargoLock lock;
  lockFile = pkgs.writeText "Cargo.lock" lock.lockFileContents;
  plan = import ./rust-cache/source-plan.nix { inherit lib; } src;
  sourceName = builtins.unsafeDiscardStringContext (
    let
      base = builtins.baseNameOf (toString src);
      match = builtins.match "[a-z0-9]{32}-(.*)" base;
    in
    if match == null then base else builtins.head match
  );
  python = pkgs.python3.withPackages (ps: [ ps.toml ]);
  dummySource =
    pkgs.runCommand sourceName
      {
        planJSON = builtins.toJSON plan;
        passAsFile = [ "planJSON" ];
      }
      ''
        ${python}/bin/python ${./rust-cache/make-source.py} "$planJSONPath" "$out"
        cp ${lockFile} "$out/Cargo.lock"
      '';
  rootPackage = plan.manifests."Cargo.toml".package or { };
  packageName =
    if pname != null then
      pname
    else
      rootPackage.name or (throw "buildRustPackage: supply pname for a virtual workspace");
  inheritedVersion = plan.manifests."Cargo.toml".workspace.package.version or null;
  manifestVersion = rootPackage.version or null;
  packageVersion =
    if version != null then
      version
    else if builtins.isAttrs manifestVersion && manifestVersion.workspace or false then
      inheritedVersion
    else if manifestVersion != null then
      manifestVersion
    else
      throw "buildRustPackage: supply version for a virtual workspace";
  target = pkgs.stdenv.hostPlatform.rust.rustcTargetSpec;
  featureArgs = lib.escapeShellArgs (
    lib.optional buildNoDefaultFeatures "--no-default-features"
    ++ lib.optionals (buildFeatures != [ ]) [
      "--features"
      (lib.concatStringsSep "," buildFeatures)
    ]
  );
  cargoArgs = "--locked --offline --target ${lib.escapeShellArg target} --profile ${lib.escapeShellArg profile} ${featureArgs}";
  cargo = command: "${rust}/bin/cargo ${command}";
  rustEnv = pkgs.rust.envVars;
  # Nixpkgs links Rust through each platform's C compiler.
  compilerEnv = platform: cc: cxx: {
    "CC_${platform.rust.cargoEnvVarTarget}" = cc;
    "CXX_${platform.rust.cargoEnvVarTarget}" = cxx;
    "CARGO_TARGET_${platform.rust.cargoEnvVarTarget}_LINKER" = cc;
  };
  generatedEnv =
    compilerEnv pkgs.stdenv.buildPlatform rustEnv.ccForBuild rustEnv.cxxForBuild
    // compilerEnv pkgs.stdenv.hostPlatform rustEnv.ccForHost rustEnv.cxxForHost
    // {
      RUSTC = "${rust}/bin/rustc";
      RUSTDOC = "${rust}/bin/rustdoc";
      HOST_CC = rustEnv.ccForBuild;
      HOST_CXX = rustEnv.cxxForBuild;
    };

  # No real source enters this record: both derivations have the same compiler
  # configuration, while dummySource owns the dependency-relevant source key.
  shared = {
    pname = packageName;
    version = packageVersion;
    env =
      generatedEnv
      // mergedEnv
      // {
        CARGO_PROFILE = profile;
      };
    buildInputs =
      defaults.buildInputs
      ++ buildInputs
      ++ lib.optionals pkgs.stdenv.hostPlatform.isDarwin [ pkgs.libiconv ];
    nativeBuildInputs =
      defaults.nativeBuildInputs
      ++ nativeBuildInputs
      ++ [
        rust
        pkgs.python3
        pkgs.zstd
      ];
    configurePhase = ''
      export CARGO_HOME="''${CARGO_HOME:-$NIX_BUILD_TOP/cargo-home}"
      export CARGO_TARGET_DIR="''${CARGO_TARGET_DIR:-$PWD/target}"
      export CARGO_BUILD_JOBS="''${CARGO_BUILD_JOBS:-$NIX_BUILD_CORES}"
      export CARGO_INCREMENTAL="''${CARGO_INCREMENTAL:-0}"
      export RUST_TEST_THREADS="''${RUST_TEST_THREADS:-$NIX_BUILD_CORES}"
      mkdir -p "$CARGO_HOME"
      # Source overrides are copied into both stages before Cargo sees them.
      cp ${lockFile} Cargo.lock
      sed 's#directory = "cargo-vendor-dir"#directory = "${vendor}"#' \
        ${vendor}/.cargo/config.toml > "$CARGO_HOME/config.toml"
    '';
    dontFixup = true;
  };
  cargoArtifacts = pkgs.stdenv.mkDerivation (
    shared
    // {
      name = "${packageName}-dependencies-${packageVersion}";
      src = dummySource;
      buildPhase = ''
        ${cargo "build"} ${cargoArgs}
        ${lib.optionalString doCheck "${cargo "test"} ${cargoArgs} --no-run"}
      '';
      installPhase = ''
        mkdir -p "$out"
        tar --sort=name --mtime=@1 --owner=0 --group=0 --numeric-owner \
          -C "$CARGO_TARGET_DIR" -cf - . | zstd -T"$NIX_BUILD_CORES" -o "$out/target.tar.zst"
      '';
    }
  );
in
assert lib.assertMsg (
  builtins.isString buildType && buildType != ""
) "buildRustPackage: buildType must be a nonempty Cargo profile name";
assert lib.assertMsg (
  builtins.isList buildFeatures && builtins.all builtins.isString buildFeatures
) "buildRustPackage: buildFeatures must be a list of feature names";
assert lib.assertMsg
  (
    checkType == buildType
    && checkFeatures == buildFeatures
    && checkNoDefaultFeatures == buildNoDefaultFeatures
  )
  "buildRustPackage: checkType, checkFeatures, and checkNoDefaultFeatures must match the build settings so compiled dependencies can be shared";
assert lib.assertMsg (
  !(mergedEnv ? CARGO_PROFILE)
) "buildRustPackage: env.CARGO_PROFILE is reserved; select the shared profile with buildType";
assert lib.assertMsg (
  !(passthru ? cargoArtifacts)
) "buildRustPackage: passthru.cargoArtifacts is reserved for generated dependency artifacts";
assert lib.assertMsg (builtins.isString packageName && builtins.isString packageVersion)
  "buildRustPackage: pname and version must be strings (supply overrides for inherited workspace identity)";
pkgs.stdenv.mkDerivation (
  shared
  // {
    inherit
      src
      name
      doCheck
      postInstall
      meta
      ;
    dontFixup = false;
    configurePhase =
      shared.configurePhase
      + ''
        mkdir -p "$CARGO_TARGET_DIR"
        zstd -dc ${cargoArtifacts}/target.tar.zst | tar -xf - -C "$CARGO_TARGET_DIR"
        chmod -R u+w "$CARGO_TARGET_DIR"
        ${cargo "metadata"} --locked --offline --no-deps --format-version 1 ${featureArgs} > "$NIX_BUILD_TOP/workspace.json"
      '';
    buildPhase = ''
      export cargoBuildLog="$NIX_BUILD_TOP/cargo-build.json"
      ${cargo "build"} ${cargoArgs} --message-format json-render-diagnostics > "$cargoBuildLog"
      ${pkgs.python3}/bin/python ${./rust-cache/install.py} \
        "$NIX_BUILD_TOP/workspace.json" "$cargoBuildLog" "$NIX_BUILD_TOP/install-artifacts"
    '';
    checkPhase = ''
      ${cargo "test"} ${cargoArgs}
    '';
    installPhase = ''
      mkdir -p "$out"
      cp -R "$NIX_BUILD_TOP/install-artifacts/." "$out/"
      runHook postInstall
    '';
    passthru = passthru // {
      inherit cargoArtifacts;
    };
  }
)
