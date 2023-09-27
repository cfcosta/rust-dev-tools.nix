{ pkgs, utils, options }:
with pkgs.lib;
let
  rust = channel: version:
    pkgs.rust-bin.${channel}.${version}.default.override {
      extensions = [ "rust-src" "clippy" "rustfmt" "rust-analyzer" ];
    };
  rustNightly = rust "nightly" "latest";

  watch = cmd: ''
    ${pkgs.cargo-watch}/bin/cargo-watch watch -s "${cmd}"
  '';

  script = name: cmd: rust: [
    (pkgs.writeShellApplication {
      name = "${options.name}-${name}";
      runtimeInputs = [ rust ];
      text = cmd;
    })

    (pkgs.writeShellScriptBin "${options.name}-watch-${name}"
      (watch "${options.name}-${name}"))
  ];

  bench = ''exec cargo bench "$@"'';
  build = ''exec cargo build "$@"'';
  check = ''exec cargo clippy --tests --benches "$@"'';
  doc = ''exec cargo doc "$@"'';
  fmt = ''exec cargo fmt "$@"'';

  bin = name: "exec ${pkgs."${name}"}/bin/${name}";

  audit = ''${bin "cargo-audit"} audit "$@"'';
  deny = ''${bin "cargo-deny"} deny "$@"'';
  expand = ''${bin "cargo-expand"} expand "$@"'';
  outdated = ''${bin "cargo-outdated"} outdated "$@"'';
  semver = ''${bin "cargo-semver-checks"} semver-checks "$@"'';
  test = "${bin "cargo-nextest"} nextest run";
  udeps = ''${bin "cargo-udeps"} udeps "$@"'';

  systemSpecificDependencies = with pkgs; rec {
    aarch64-darwin = [ darwin.apple_sdk.frameworks.SystemConfiguration ]
      ++ optionals options.overrides.darwin.useLLD [ lld_14 ];
    x86_64-darwin = aarch64-darwin;

    x86_64-linux = [ ] ++ optionals options.overrides.linux.useMold [ mold ];
    aarch64-linux = x86_64-linux;
  };

  systemFlags = with pkgs.lib; rec {
    x86_64-darwin = [ ] ++ optionals options.overrides.darwin.useLLD
      [ "-C link-arg=-fuse-ld=lld" ];
    aarch64-darwin = x86_64-darwin;

    x86_64-linux = [ ] ++ optionals options.overrides.linux.useMold
      [ "-C link-arg=-fuse-ld=mold" ];
    aarch64-linux = x86_64-linux;
  };

  depsWithLibs = builtins.filter utils.containsLibraries options.dependencies;

  versionFromPackage = toml:
    if builtins.hasAttr "package" toml
    && builtins.hasAttr "rust-version" toml.package then
      toml.package.rust-version
    else
      null;

  versionFromWorkspace = toml:
    if builtins.hasAttr "workspace" toml
    && builtins.hasAttr "package" toml.workspace
    && builtins.hasAttr "rust-version" toml.workspace.package then
      toml.workspace.package.rust-version
    else
      null;

  findRust = {
    toolchain = rust options.rust.channel options.rust.version;
    toolchainFile = pkgs.rust-bin.fromRustupToolchainFile options.rust.file;
    cargo = let
      toml = builtins.fromTOML (builtins.readFile options.rust.file);
      version = utils.firstNonNull [
        (versionFromWorkspace toml)
        (versionFromPackage toml)
        "latest"
      ];
    in rust "stable" version;
  }.${options.rust.source};

  flagsFromCargoConfig = if options.cargoConfig == null then
    [ ]
  else
    let toml = (builtins.fromTOML (builtins.readFile options.cargoConfig));
    in if builtins.hasAttr "build" toml
    && builtins.hasAttr "rustflags" toml.build then
      toml.build.rustflags
    else
      [ ];
in {
  inherit findRust;

  env = {
    RUSTFLAGS = concatStringsSep " "
      ((systemFlags.${pkgs.system}) ++ flagsFromCargoConfig);
    LD_LIBRARY_PATH =
      makeLibraryPath (depsWithLibs ++ [ pkgs.stdenv.cc.cc.lib ]);
  };

  packages = [
    (pkgs.writeShellScriptBin "${options.name}-watch"
      (watch "${options.name}-check"))

    (script "bench" bench findRust)
    (script "build" build findRust)
    (script "check" check findRust)
    (script "doc" doc findRust)
    (script "fmt" fmt findRust)

    (script "audit" audit findRust)
    (script "deny" deny findRust)
    (script "expand" expand findRust)
    (script "outdated" outdated findRust)
    (script "semver" semver findRust)
    (script "test" test findRust)

    (script "udeps" udeps rustNightly)
  ] ++ systemSpecificDependencies."${pkgs.system}";
}
