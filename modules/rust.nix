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
  expand = ''${bin "cargo-expand"} expand "$@"'';
  semver = ''${bin "cargo-semver-checks"} semver-checks "$@"'';
  test = "${bin "cargo-nextest"} nextest run";
  udeps = ''${bin "cargo-udeps"} udeps "$@"'';

  systemSpecificDependencies = with pkgs; rec {
    aarch64-darwin = [ darwin.apple_sdk.frameworks.SystemConfiguration lld_14 ];
    x86_64-darwin = aarch64-darwin;

    x86_64-linux = [ mold ];
    aarch64-linux = x86_64-linux;
  };

  systemFlags = with pkgs; rec {
    x86_64-darwin = [ "-C link-arg=-fuse-ld=lld" ];
    aarch64-darwin = x86_64-darwin;

    x86_64-linux = [ "-C link-arg=-fuse-ld=mold" ];
    aarch64-linux = x86_64-linux;
  };

  depsWithLibs = builtins.filter utils.containsLibraries options.dependencies;

  fromCargo = let
    toml = builtins.fromTOML (builtins.readFile options.cargoToml);

    version = if builtins.hasAttr "package" toml
    && builtins.hasAttr "rust-version" toml.package then
      toml.package.rust-version
    else
      "latest";
  in rust "stable" version;

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
  inherit fromCargo;

  env = {
    RUSTFLAGS = concatStringsSep " "
      ((systemFlags.${pkgs.system}) ++ flagsFromCargoConfig);
    LD_LIBRARY_PATH =
      makeLibraryPath (depsWithLibs ++ [ pkgs.stdenv.cc.cc.lib ]);
  };

  packages = [
    (pkgs.writeShellScriptBin "${options.name}-watch"
      (watch "${options.name}-check"))

    (script "bench" bench fromCargo)
    (script "build" build fromCargo)
    (script "check" check fromCargo)
    (script "doc" doc fromCargo)
    (script "fmt" fmt fromCargo)

    (script "audit" audit fromCargo)
    (script "expand" expand fromCargo)
    (script "semver" semver fromCargo)
    (script "test" test fromCargo)

    (script "udeps" udeps rustNightly)
  ] ++ systemSpecificDependencies."${pkgs.system}";
}
