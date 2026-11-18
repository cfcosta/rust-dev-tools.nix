# One derivation per planned crate: the crate compiled exactly as the build
# that planned it compiles it. A derivation's inputs are the crate, its
# features, the crates it needs, the toolchain, the flags and profile that
# enter Cargo's unit key, and the native inputs the crate itself declares.
# Builds that plan the same crate the same way share its derivation.
{
  pkgs,
  lib,
  rust,
  python,
  target,
  profile,
  rustflags,
  manifestProfile,
  config,
  lockFileContents,
  crateOverrides,
  configure,
  env,
}:
nodes:
let
  lock = builtins.fromTOML lockFileContents;
  packages = lock.package or [ ];
  key = package: "${package.name} ${package.version}";
  byKey = lib.listToAttrs (map (package: lib.nameValuePair (key package) package) packages);
  byName = lib.groupBy (package: package.name) packages;

  # A lockfile dependency is `name`, `name version`, or `name version (source)`.
  resolve =
    ref:
    let
      parts = lib.splitString " " ref;
    in
    if builtins.length parts == 1 then
      key (builtins.head byName.${ref})
    else
      "${builtins.elemAt parts 0} ${builtins.elemAt parts 1}";

  # Every locked package reachable from `roots`, on any platform: Cargo
  # resolves a lockfile across all targets, so the vendored crates must too.
  lockClosure =
    roots:
    map (entry: byKey.${entry.key}) (
      builtins.genericClosure {
        startSet = map (name: { key = name; }) roots;
        operator = entry: map (ref: { key = resolve ref; }) (byKey.${entry.key}.dependencies or [ ]);
      }
    );

  renderLock =
    entries:
    lib.concatMapStrings (package: ''
      [[package]]
      name = ${builtins.toJSON package.name}
      version = ${builtins.toJSON package.version}
      source = ${builtins.toJSON package.source}
      checksum = ${builtins.toJSON package.checksum}

    '') entries;

  rustPlatform = pkgs.makeRustPlatform {
    cargo = rust;
    rustc = rust;
  };

  # Cargo wants one name per crate version, even across dependency kinds.
  alias =
    node: "u_${builtins.substring 0 16 (builtins.hashString "sha256" "${node.name}@${node.version}")}";

  overrides = pkgs.defaultCrateOverrides // crateOverrides;
  # The native inputs and environment a crate declares, from Nixpkgs'
  # crate overrides or the package's own.
  overrideFor =
    node:
    let
      found = overrides.${node.name} or null;
      result =
        if found == null then
          { }
        else
          found {
            crateName = node.name;
            inherit (node) version features;
            dependencies = [ ];
            buildDependencies = [ ];
          };
      field =
        name: fallback:
        let
          attempt = builtins.tryEval (result.${name} or fallback);
        in
        if attempt.success then attempt.value else fallback;
    in
    {
      buildInputs = field "buildInputs" [ ];
      nativeBuildInputs = field "nativeBuildInputs" [ ];
      env = field "env" { };
      preBuild = field "preBuild" "";
    };

  closureOf =
    index:
    map (entry: entry.key) (
      builtins.genericClosure {
        startSet = map (dep: { key = dep; }) (builtins.elemAt nodes index).deps;
        operator = entry: map (dep: { key = dep; }) (builtins.elemAt nodes entry.key).deps;
      }
    );

  build =
    index:
    let
      node = builtins.elemAt nodes index;
      needed = map (builtins.elemAt nodes) ([ index ] ++ closureOf index);
      locked = lockClosure (map (dep: "${dep.name} ${dep.version}") needed);
      lockText = renderLock locked;
      vendor = rustPlatform.importCargoLock { lockFileContents = lockText; };
      # What this crate and every crate it needs declare: a dependent checks
      # their build scripts again, and links what they found.
      override = {
        buildInputs = lib.unique (lib.concatMap (dep: (overrideFor dep).buildInputs) needed);
        nativeBuildInputs = lib.unique (lib.concatMap (dep: (overrideFor dep).nativeBuildInputs) needed);
        env = lib.foldl' (env: dep: env // (overrideFor dep).env) { } needed;
        preBuild = lib.concatStrings (lib.unique (map (dep: (overrideFor dep).preBuild) needed));
      };
      spec = {
        lockVersion = lock.version or 3;
        deps = map (dep: {
          inherit (dep)
            name
            version
            host
            features
            ;
          alias = alias dep;
        }) needed;
        packages = map (package: {
          inherit (package)
            name
            version
            source
            checksum
            ;
          dependencies = package.dependencies or [ ];
        }) locked;
        profile = manifestProfile;
        inherit config;
      };
      src =
        pkgs.runCommand "rust-unit-${node.name}-${node.version}-source"
          {
            specJSON = builtins.toJSON spec;
            passAsFile = [ "specJSON" ];
          }
          ''
            ${python}/bin/python ${./make-unit.py} "$specJSONPath" "$out"
          '';
      layers = lib.unique (
        lib.concatMap (dep: units.${toString dep}.passthru.layers ++ [ units.${toString dep} ]) node.deps
      );
    in
    pkgs.stdenv.mkDerivation {
      pname = "rust-unit-${node.name}${lib.optionalString node.host "-host"}";
      inherit (node) version;
      inherit src;
      env =
        env
        // override.env
        // {
          RUSTFLAGS = rustflags;
        };
      buildInputs = override.buildInputs;
      nativeBuildInputs = override.nativeBuildInputs ++ [
        rust
        pkgs.pkg-config
        pkgs.zstd
      ];
      configurePhase = configure vendor + ''
        mkdir -p "$CARGO_TARGET_DIR"
        ${lib.concatMapStrings (layer: ''
          zstd -dc ${layer}/target.tar.zst | tar -xf - -C "$CARGO_TARGET_DIR"
        '') layers}
        chmod -R u+w "$CARGO_TARGET_DIR"
        touch "$NIX_BUILD_TOP/layers-unpacked"
      '';
      buildPhase = ''
        ${override.preBuild}
        ${rust}/bin/cargo build --offline --target ${lib.escapeShellArg target} --profile ${lib.escapeShellArg profile}
      '';
      installPhase = ''
        mkdir -p "$out"
        # Only this crate: the workspace's own package and Cargo's
        # bookkeeping belong to no unit.
        (cd "$CARGO_TARGET_DIR" && find . ! -type d -newer "$NIX_BUILD_TOP/layers-unpacked" \
          ! -path '*/build/rdt-unit/*' ! -name '*rdt_unit*' ! -name '*rdt-unit*' \
          ! -name .cargo-lock ! -name .rustc_info.json ! -name CACHEDIR.TAG -print0) |
          LC_ALL=C sort -z |
          tar --mtime=@1 --owner=0 --group=0 --numeric-owner \
            -C "$CARGO_TARGET_DIR" --null -T - -cf - | zstd -T"$NIX_BUILD_CORES" -o "$out/target.tar.zst"
      '';
      dontFixup = true;
      passthru = {
        inherit layers;
        nativeInputs = { inherit (override) buildInputs nativeBuildInputs env; };
      };
    };

  units = lib.listToAttrs (
    lib.imap0 (index: _: lib.nameValuePair (toString index) (build index)) nodes
  );
in
lib.genList (index: units.${toString index}) (builtins.length nodes)
