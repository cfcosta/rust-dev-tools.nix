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

  rust = pkgs.rust-bin.${options.rust.channel}.${options.rust.version}.default.override {
    extensions = [
      "rust-src"
      "clippy"
      "rustfmt"
      "rust-analyzer"
      "llvm-tools-preview"
    ];
  };

  env = {
    RUSTFLAGS = concatStringsSep " " ((systemFlags.${pkgs.system}) ++ flagsFromCargoConfig);
    LD_LIBRARY_PATH = makeLibraryPath (
      (filter utils.containsLibraries options.dependencies) ++ [ pkgs.stdenv.cc.cc.lib ]
    );
  };

  createRustPlatform = pkgs.makeRustPlatform {
    cargo = rust;
    rustc = rust;
  };

  buildRustPackage =
    {
      name ? options.name,
      buildInputs ? [ ],
      nativeBuildInputs ? [ ],
      ...
    }@args:
    let
      rustPlatform = createRustPlatform;
      defaultBuildInputs = options.dependencies;
      defaultNativeBuildInputs = [ pkgs.pkg-config ] ++ systemSpecificDependencies.${pkgs.system};
    in
    rustPlatform.buildRustPackage (
      args
      // {
        inherit name;

        buildInputs = defaultBuildInputs ++ buildInputs;
        nativeBuildInputs = defaultNativeBuildInputs ++ nativeBuildInputs;

        env = {
          RUSTFLAGS = concatStringsSep " " ((systemFlags.${pkgs.system}) ++ flagsFromCargoConfig);
          LD_LIBRARY_PATH = makeLibraryPath (
            (filter utils.containsLibraries options.dependencies) ++ [ pkgs.stdenv.cc.cc.lib ]
          );
        };
      }
    );

  watch = cmd: ''
    exec ${pkgs.cargo-watch}/bin/cargo-watch watch -s "${cmd} ''${@}"
  '';

  script =
    name: cmd:
    let
      baseScript = pkgs.writeShellApplication {
        name = "${options.name}-${name}";
        runtimeInputs = [ rust ];
        text = ''
          export CARGO="${rust}/bin/cargo"
          export RUSTC="${rust}/bin/rustc"
          export RUSTFLAGS="${env.RUSTFLAGS}"

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

    "x86_64-linux" = optionals linux.useMold [
      "-C link-arg=-fuse-ld=mold"
      "-C link-arg=-Wl,--separate-debug-file"
    ];
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

  createPackages = mapAttrs (name: cmd: script name cmd);
in
{
  inherit
    createRustPlatform
    buildRustPackage
    env
    rust
    ;

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
      ++ systemSpecificDependencies.${pkgs.system};
  };
}
