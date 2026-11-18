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
  cargoPackages ? [ ],
  checkPackages ? cargoPackages,
  doCheck ? true,
  useNextest ? false,
  nativeCheckInputs ? [ ],
  preBuildDependencies ? "",
  preBuild ? "",
  postInstall ? "",
  postFixup ? "",
  desktopItems ? [ ],
  doInstallCheck ? false,
  installCheckPhase ? null,
  disallowedReferences ? [ ],
  dependencyLayers ? [ ],
  unitPlan ? null,
  crateOverrides ? { },
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
  packageArgs =
    packages:
    lib.escapeShellArgs (
      lib.concatMap (p: [
        "--package"
        p
      ]) packages
    );
  buildArgs = "${cargoArgs} ${packageArgs cargoPackages}";
  checkArgs = "${cargoArgs} ${packageArgs checkPackages}";
  # nextest names Cargo's profile --cargo-profile; --profile is its own.
  nextestArgs = "--locked --offline --target ${lib.escapeShellArg target} --cargo-profile ${lib.escapeShellArg profile} ${featureArgs} ${packageArgs checkPackages}";
  cargo = command: "${rust}/bin/cargo ${command}";
  # Compiled dependencies from other builds, each layer's own layers first.
  # Cargo keys a unit by its inputs and not by workspace, so a unit another
  # build left behind is fresh here when this build needs the same one.
  layers = lib.unique (
    lib.concatMap (layer: layer.passthru.layers ++ [ layer ]) (dependencyLayers ++ plannedUnits)
  );
  unpack = artifacts: ''
    zstd -dc ${artifacts}/target.tar.zst | tar -xf - -C "$CARGO_TARGET_DIR"
  '';
  # Cargo's environment for a build whose crates are vendored in `vendor`.
  configure = vendor: ''
    export CARGO_HOME="''${CARGO_HOME:-$NIX_BUILD_TOP/cargo-home}"
    export CARGO_TARGET_DIR="''${CARGO_TARGET_DIR:-$PWD/target}"
    export CARGO_BUILD_JOBS="''${CARGO_BUILD_JOBS:-$NIX_BUILD_CORES}"
    export CARGO_INCREMENTAL="''${CARGO_INCREMENTAL:-0}"
    export RUST_TEST_THREADS="''${RUST_TEST_THREADS:-$NIX_BUILD_CORES}"
    # Cargo's unit keys include RUSTFLAGS and its freshness checks the
    # source path, so the vendored crates sit at one path in every build:
    # a unit compiled for another package is then the same unit here. The
    # Linux sandbox always builds in /build; elsewhere the build directory
    # varies, and the store path at least stays the same in both stages.
    if [ "$NIX_BUILD_TOP" = /build ]; then
      vendorDir=/build/cargo-vendor-dir
      ln -sfn ${vendor} "$vendorDir"
      # Build scripts that use pkg-config record PKG_CONFIG_PATH, which each
      # derivation's inputs set differently. One directory of the inputs'
      # .pc files keeps the recorded value, so the script stays fresh.
      mkdir -p /build/rdt-pkg-config
      for dir in ''${PKG_CONFIG_PATH//:/ } ''${PKG_CONFIG_PATH_FOR_BUILD//:/ }; do
        for file in "$dir"/*.pc; do
          [ -e "$file" ] && ln -sn "$file" /build/rdt-pkg-config/ 2>/dev/null || true
        done
      done
      export PKG_CONFIG_PATH=/build/rdt-pkg-config PKG_CONFIG_PATH_FOR_BUILD=/build/rdt-pkg-config
    else
      vendorDir=${vendor}
    fi
    # Panic locations name source files. Remapping the vendored crates and
    # the toolchain's rust-src keeps both out of the package's closure.
    export RUSTFLAGS="''${RUSTFLAGS:-} --remap-path-prefix=$vendorDir=/cargo-vendor-dir --remap-path-prefix=$(${rust}/bin/rustc --print sysroot)=/rust-toolchain"
    mkdir -p "$CARGO_HOME"
    sed "s#directory = \"cargo-vendor-dir\"#directory = \"$vendorDir\"#" \
      ${vendor}/.cargo/config.toml > "$CARGO_HOME/config.toml"
  '';

  # A committed plan of the registry crates this build compiles, which then
  # come ready-made from one derivation each (rust-cache/units.nix). The key
  # names the selection, `inputs` the manifests and lockfile it was made from.
  unitSelection = {
    packages = cargoPackages;
    inherit
      checkPackages
      target
      profile
      doCheck
      ;
    features = buildFeatures;
    noDefaultFeatures = buildNoDefaultFeatures;
  };
  unitKey = builtins.hashString "sha256" (builtins.toJSON unitSelection);
  unitInputs = builtins.hashString "sha256" (
    builtins.toJSON {
      inherit (plan) manifests configs;
      inherit (lock) lockFileContents;
    }
  );
  plannedEntry =
    if unitPlan != null && builtins.pathExists unitPlan then
      (lib.importJSON unitPlan).plans.${unitKey} or null
    else
      null;
  planIsCurrent = plannedEntry != null && plannedEntry.inputs == unitInputs;
  plannedUnits =
    if planIsCurrent then
      import ./rust-cache/units.nix {
        inherit
          pkgs
          lib
          rust
          python
          target
          profile
          configure
          crateOverrides
          ;
        inherit (lock) lockFileContents;
        env = generatedEnv;
        rustflags = mergedEnv.RUSTFLAGS or "";
        manifestProfile = plan.manifests."Cargo.toml".profile or null;
        config = plan.configs.".cargo/config.toml" or plan.configs.".cargo/config" or null;
      } plannedEntry.nodes
    else if unitPlan != null then
      builtins.trace
        "rdt: ${packageName} has no current unit plan, so its dependencies build in one derivation; run `nix run github:cfcosta/rust-dev-tools.nix#plan` to write one"
        [ ]
    else
      [ ];

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
      # The environment the planned crates' build scripts recorded, so they
      # stay fresh here.
      // lib.foldl' (env: unit: env // unit.passthru.nativeInputs.env) { } plannedUnits
      // mergedEnv
      // {
        CARGO_PROFILE = profile;
      };
    buildInputs =
      defaults.buildInputs
      ++ buildInputs
      ++ lib.concatMap (unit: unit.passthru.nativeInputs.buildInputs) plannedUnits
      ++ lib.optionals pkgs.stdenv.hostPlatform.isDarwin [ pkgs.libiconv ];
    nativeBuildInputs =
      defaults.nativeBuildInputs
      ++ nativeBuildInputs
      ++ lib.concatMap (unit: unit.passthru.nativeInputs.nativeBuildInputs) plannedUnits
      ++ [
        rust
        pkgs.python3
        pkgs.zstd
      ];
    configurePhase = configure vendor + ''
      # Source overrides are copied into both stages before Cargo sees them.
      cp ${lockFile} Cargo.lock
    '';
    dontFixup = true;
  };
  cargoArtifacts = pkgs.stdenv.mkDerivation (
    shared
    // {
      name = "${packageName}-dependencies-${packageVersion}";
      src = dummySource;
      preBuild = preBuildDependencies;
      configurePhase = shared.configurePhase + ''
        mkdir -p "$CARGO_TARGET_DIR"
        ${lib.concatMapStrings unpack layers}
        chmod -R u+w "$CARGO_TARGET_DIR"
        # Unpacked files carry mtime 1; whatever this build writes is newer.
        touch "$NIX_BUILD_TOP/layers-unpacked"
      '';
      buildPhase = ''
        runHook preBuild
        ${cargo "build"} ${buildArgs}
        ${lib.optionalString doCheck "${cargo "test"} ${checkArgs} --no-run"}
      '';
      installPhase = ''
        mkdir -p "$out"
        # Only what the layers lack: the final stage unpacks them first.
        (cd "$CARGO_TARGET_DIR" && find . ! -type d -newer "$NIX_BUILD_TOP/layers-unpacked" -print0) |
          LC_ALL=C sort -z |
          tar --mtime=@1 --owner=0 --group=0 --numeric-owner \
            -C "$CARGO_TARGET_DIR" --null -T - -cf - | zstd -T"$NIX_BUILD_CORES" -o "$out/target.tar.zst"
      '';
      passthru = { inherit layers; };
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
  !(passthru ? cargoArtifacts || passthru ? buildOnly)
) "buildRustPackage: passthru.cargoArtifacts and passthru.buildOnly are reserved for the builder";
assert lib.assertMsg (builtins.all builtins.isString (
  cargoPackages ++ checkPackages
)) "buildRustPackage: cargoPackages and checkPackages must be lists of Cargo package names";
assert lib.assertMsg (builtins.isString packageName && builtins.isString packageVersion)
  "buildRustPackage: pname and version must be strings (supply overrides for inherited workspace identity)";
pkgs.stdenv.mkDerivation (
  shared
  // {
    inherit
      src
      name
      doCheck
      preBuild
      postInstall
      postFixup
      desktopItems
      doInstallCheck
      disallowedReferences
      meta
      ;
    dontFixup = false;
    configurePhase = shared.configurePhase + ''
      mkdir -p "$CARGO_TARGET_DIR"
      ${lib.concatMapStrings unpack (layers ++ [ cargoArtifacts ])}
      chmod -R u+w "$CARGO_TARGET_DIR"
      ${cargo "metadata"} --locked --offline --no-deps --format-version 1 ${featureArgs} > "$NIX_BUILD_TOP/workspace.json"
    '';
    buildPhase = ''
      runHook preBuild
      export cargoBuildLog="$NIX_BUILD_TOP/cargo-build.json"
      ${cargo "build"} ${buildArgs} --message-format json-render-diagnostics > "$cargoBuildLog"
      ${pkgs.python3}/bin/python ${./rust-cache/install.py} \
        "$NIX_BUILD_TOP/workspace.json" "$cargoBuildLog" "$NIX_BUILD_TOP/install-artifacts"
    '';
    checkPhase =
      if useNextest then
        ''
          ${cargo "nextest run"} ${nextestArgs}
        ''
      else
        ''
          ${cargo "test"} ${checkArgs}
        '';
    nativeCheckInputs = nativeCheckInputs ++ lib.optionals useNextest [ pkgs.cargo-nextest ];
    installPhase = ''
      mkdir -p "$out"
      cp -R "$NIX_BUILD_TOP/install-artifacts/." "$out/"
      runHook postInstall
    '';
    passthru = passthru // {
      inherit cargoArtifacts;
      # What `nix run github:cfcosta/rust-dev-tools.nix#plan` plans.
      unitPlan = unitSelection // {
        key = unitKey;
        inputs = unitInputs;
        toolchain = rust;
        units = builtins.length plannedUnits;
      };
      # The build-time paths the remapping keeps out of the closure.
      buildOnly = [
        vendor
        (rust.sysroot or rust)
      ];
    };
  }
  // lib.optionalAttrs (installCheckPhase != null) { inherit installCheckPhase; }
)
