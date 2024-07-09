{ pkgs, utils, options }:
let
  inherit (builtins) readFile hasAttr;
  inherit (pkgs.lib) concatStringsSep optionals makeLibraryPath filter;

  rust = channel: version:
    pkgs.rust-bin.${channel}.${version}.default.override {
      extensions =
        [ "rust-src" "clippy" "rustfmt" "rust-analyzer" "llvm-tools-preview" ];
    };

  findRust = versionSpec:
    if versionSpec == null then
      {
        toolchain = rust options.rust.channel options.rust.version;
        toolchainFile = pkgs.rust-bin.fromRustupToolchainFile options.rust.file;
        cargo = let
          toml = fromTOML (readFile options.rust.file);
          version = utils.firstNonNull [
            (versionFromWorkspace toml)
            (versionFromPackage toml)
            "latest"
          ];
        in rust "stable" version;
      }.${options.rust.source}
    else
      rust versionSpec.channel versionSpec.version;

  createRustPlatform = versionSpec:
    let
      rustc = findRust versionSpec;
    in
    pkgs.makeRustPlatform {
      cargo = rustc;
      rustc = rustc;
    };

  nightlyScript = name: cmd:
    if options.enableNightlyTools then
      script name cmd (rust "nightly" "latest")
    else
      null;

  versionFromPackage = toml:
    if hasAttr "package" toml && hasAttr "rust-version" toml.package then
      toml.package.rust-version
    else
      null;

  versionFromWorkspace = toml:
    if hasAttr "workspace" toml && hasAttr "package" toml.workspace
    && hasAttr "rust-version" toml.workspace.package then
      toml.workspace.package.rust-version
    else
      null;

  watch = cmd: ''
    exec ${pkgs.cargo-watch}/bin/cargo-watch watch -s "${cmd} ''${@}"
  '';

  script = name: cmd: rust: [
    (pkgs.writeShellApplication {
      name = "${options.name}-${name}";
      runtimeInputs = [ rust ];
      text = ''
        export CARGO="${rust}/bin/cargo"
        export RUSTC="${rust}/bin/rustc"

        exec ${cmd} "''${@}"
      '';
      checkPhase = "";
    })
    (pkgs.writeShellApplication {
      name = "${options.name}-watch-${name}";
      text = watch "${options.name}-${name}";
      checkPhase = "";
    })
  ];

  bench = "cargo bench";
  build = "cargo build";
  check = "cargo clippy --tests --benches";
  doc = "cargo doc";
  fmt = "cargo fmt";

  bin = name: "${pkgs."${name}"}/bin/${name}";

  audit = "${bin "cargo-audit"} audit";
  deny = "${bin "cargo-deny"} deny";
  expand = "${bin "cargo-expand"} expand";
  outdated = "${bin "cargo-outdated"} outdated";
  semver = "${bin "cargo-semver-checks"} semver-checks";
  test = "${bin "cargo-nextest"} nextest run";
  udeps = "${bin "cargo-udeps"} udeps";
  mutants = "${bin "cargo-mutants"} mutants";
  llvm-cov = "${bin "cargo-llvm-cov"} llvm-cov";

  systemSpecificDependencies = with pkgs; rec {
    inherit (darwin.apple_sdk.frameworks) CoreFoundation CoreServices SystemConfiguration;
    inherit (options.overrides) darwin linux;
    inherit lld_14 mold;

    aarch64-darwin = [
      CoreFoundation
      CoreServices
      SystemConfiguration
    ] ++ optionals darwin.useLLD [ lld_14 ];
    x86_64-darwin = aarch64-darwin;

    x86_64-linux = [ (nightlyScript "llvm-cov" llvm-cov) ]
      ++ optionals linux.useMold [ mold ];
    aarch64-linux = x86_64-linux;
  };

  systemFlags = rec {
    inherit (options.overrides) darwin linux;

    x86_64-darwin = [ ] ++ optionals darwin.useLLD
      [ "-C link-arg=-fuse-ld=lld" ];
    aarch64-darwin = x86_64-darwin;

    x86_64-linux = [ ] ++ optionals linux.useMold
      [ "-C link-arg=-fuse-ld=mold" ];
    aarch64-linux = x86_64-linux;
  };

  flagsFromCargoConfig = if options.cargoConfig == null then
    [ ]
  else
    let toml = (fromTOML (readFile options.cargoConfig));
    in if hasAttr "build" toml && hasAttr "rustflags" toml.build then
      toml.build.rustflags
    else
      [ ];
in {
  inherit findRust createRustPlatform;

  env = {
    RUSTFLAGS = concatStringsSep " "
      ((systemFlags.${pkgs.system}) ++ flagsFromCargoConfig);
    LD_LIBRARY_PATH = makeLibraryPath
      ((filter utils.containsLibraries options.dependencies)
        ++ [ pkgs.stdenv.cc.cc.lib ]);
  };

  packages = [
    # Necessary for all dependencies that include libs
    pkgs.pkg-config
    pkgs.cargo-watch

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
    (script "mutants" mutants findRust)
    (script "outdated" outdated findRust)
    (script "semver" semver findRust)
    (script "test" test findRust)

    (nightlyScript "udeps" udeps)
  ] ++ systemSpecificDependencies."${pkgs.system}";
}