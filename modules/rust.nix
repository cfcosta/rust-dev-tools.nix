{
  pkgs,
  utils,
  options,
}:
let
  inherit (builtins) readFile hasAttr fromTOML;
  inherit (pkgs.lib)
    concatStringsSep
    optionals
    makeLibraryPath
    filter
    mapAttrs
    attrValues
    ;
  inherit (options.overrides) darwin linux;

  rust =
    channel: version:
    let
      rustPackage = pkgs.rust-bin.${channel}.${version}.default.override {
        extensions = [
          "rust-src"
          "clippy"
          "rustfmt"
          "rust-analyzer"
          "llvm-tools-preview"
        ];
      };
    in
    {
      inherit rustPackage;
    };

  findRust =
    versionSpec:
    let
      defaultRust = rust "stable" "latest";
      rustFromSpec =
        if builtins.isAttrs versionSpec && versionSpec ? channel && versionSpec ? version then
          rust versionSpec.channel versionSpec.version
        else if builtins.isString versionSpec then
          rust "stable" versionSpec
        else
          defaultRust;
    in
    if versionSpec == null then
      {
        toolchain = rust options.rust.channel options.rust.version;
        toolchainFile = pkgs.rust-bin.fromRustupToolchainFile options.rust.file;
        cargo =
          let
            toml = fromTOML (readFile options.rust.file);
            version = utils.firstNonNull [
              (versionFromWorkspace toml)
              (versionFromPackage toml)
              "latest"
            ];
          in
          rust "stable" version;
      }
      .${options.rust.source}
    else
      rustFromSpec;

  createRustPlatform =
    input:
    let
      rustPackage =
        if builtins.isAttrs input && input ? outPath then input else (findRust input).rustPackage;
    in
    pkgs.makeRustPlatform {
      cargo = rustPackage;
      rustc = rustPackage;
    };

  nightlyScript =
    name: cmd: if options.enableNightlyTools then script name cmd (rust "nightly" "latest") else null;

  versionFromPackage =
    toml:
    if hasAttr "package" toml && hasAttr "rust-version" toml.package then
      toml.package.rust-version
    else
      null;

  versionFromWorkspace =
    toml:
    if
      hasAttr "workspace" toml
      && hasAttr "package" toml.workspace
      && hasAttr "rust-version" toml.workspace.package
    then
      toml.workspace.package.rust-version
    else
      null;

  watch = cmd: ''
    exec ${pkgs.cargo-watch}/bin/cargo-watch watch -s "${cmd} ''${@}"
  '';

  script =
    name: cmd: rust:
    let
      rustPackage =
        if builtins.isAttrs rust && rust ? rustPackage then
          rust.rustPackage
        else if builtins.isAttrs rust && rust ? outPath then
          rust
        else
          (findRust rust).rustPackage;

      baseScript = pkgs.writeShellApplication {
        name = "${options.name}-${name}";
        runtimeInputs = [ rustPackage ];
        text = ''
          export CARGO="${rustPackage}/bin/cargo"
          export RUSTC="${rustPackage}/bin/rustc"
          export RUSTFLAGS="$RUSTFLAGS ''${RUSTFLAGS:-}"

          exec ${cmd} "''${@}"
        '';
        checkPhase = "";
      };
      watchScript = pkgs.writeShellApplication {
        name = "${options.name}-watch-${name}";
        runtimeInputs = [ pkgs.cargo-watch ];
        text = ''
          exec ${pkgs.cargo-watch}/bin/cargo-watch -x "${options.name}-${name} ''${*}"
        '';
        checkPhase = "";
      };
    in
    pkgs.symlinkJoin {
      name = "${options.name}-${name}-combined";
      paths = [
        baseScript
        watchScript
      ];
    };

  cargoCommands = {
    bench = "cargo bench";
    build = "cargo build";
    check = "cargo clippy --tests --benches";
    doc = "cargo doc";
    fmt = "cargo fmt";
  };

  bin = name: "${pkgs."${name}"}/bin/${name}";

  cargoExtensions = {
    audit = "${bin "cargo-audit"} audit";
    deny = "${bin "cargo-deny"} deny";
    expand = "${bin "cargo-expand"} expand";
    outdated = "${bin "cargo-outdated"} outdated";
    semver = "${bin "cargo-semver-checks"} semver-checks";
    test = "${bin "cargo-nextest"} nextest run";
    udeps = "${bin "cargo-udeps"} udeps";
    mutants = "${bin "cargo-mutants"} mutants";
  };

  systemSpecificDependencies = {
    "aarch64-darwin" =
      (with pkgs.darwin.apple_sdk.frameworks; [
        CoreFoundation
        CoreServices
        SystemConfiguration
        Security
      ])
      ++ optionals darwin.useLLD [ pkgs.lld ];
    "x86_64-darwin" = systemSpecificDependencies."aarch64-darwin";

    "x86_64-linux" = optionals linux.useMold [ pkgs.mold ];
    "aarch64-linux" = systemSpecificDependencies."x86_64-linux";
  };

  systemFlags = {
    inherit (options.overrides) darwin linux;

    "x86_64-darwin" = optionals darwin.useLLD [ "-C link-arg=-fuse-ld=lld" ];
    "aarch64-darwin" = systemFlags."x86_64-darwin";

    "x86_64-linux" = optionals linux.useMold [ "-C link-arg=-fuse-ld=mold" ];
    "aarch64-linux" = systemFlags."x86_64-linux";
  };

  flagsFromCargoConfig =
    if options.cargoConfig == null then
      [ ]
    else
      let
        toml = (fromTOML (readFile options.cargoConfig));
      in
      if hasAttr "build" toml && hasAttr "rustflags" toml.build then toml.build.rustflags else [ ];

  createPackages = mapAttrs (name: cmd: script name cmd findRust);
in
{
  inherit findRust createRustPlatform;

  env = {
    RUSTFLAGS = concatStringsSep " " ((systemFlags.${pkgs.system}) ++ flagsFromCargoConfig);
    LD_LIBRARY_PATH = makeLibraryPath (
      (filter utils.containsLibraries options.dependencies) ++ [ pkgs.stdenv.cc.cc.lib ]
    );
  };

  packages = pkgs.symlinkJoin {
    name = "${options.name}-packages";
    paths =
      [
        pkgs.pkg-config
        pkgs.cargo-watch

        (pkgs.writeShellScriptBin "${options.name}-watch" (watch "${options.name}-check"))
      ]
      ++ (attrValues (createPackages cargoCommands))
      ++ (attrValues (createPackages cargoExtensions))
      ++ [ (nightlyScript "udeps" cargoExtensions.udeps) ]
      ++ systemSpecificDependencies.${pkgs.system};
  };
}
