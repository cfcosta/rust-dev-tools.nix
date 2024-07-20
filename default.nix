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
  inherit (pkgs.stdenv) mkDerivation;

  # Rust setup
  rustOptions = options.rust // {
    channel = "stable";
    version = "latest";
  };
  rust = pkgs.rust-bin.${rustOptions.channel}.${rustOptions.version}.complete;

  createRustPlatform = pkgs.makeRustPlatform {
    cargo = rust;
    rustc = rust;
  };

  # Environment and flags
  flagsFromCargoConfig =
    if options.cargoConfig == null then
      [ ]
    else
      let
        toml = fromTOML (readFile options.cargoConfig);
      in
      if hasAttr "build" toml && hasAttr "rustflags" toml.build then toml.build.rustflags else [ ];

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

  env = {
    RUSTFLAGS = concatStringsSep " " ((systemFlags.${pkgs.system}) ++ flagsFromCargoConfig);
    LD_LIBRARY_PATH = makeLibraryPath (
      (filter utils.containsLibraries options.dependencies) ++ [ pkgs.stdenv.cc.cc.lib ]
    );
  };

  # System-specific dependencies
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

  # Build functions
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
        inherit name env;
        buildInputs = defaultBuildInputs ++ buildInputs;
        nativeBuildInputs = defaultNativeBuildInputs ++ nativeBuildInputs;
      }
    );

  # Script generation
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

  # Cargo commands and extensions
  cargoCommands = {
    bench = "${rust}/bin/cargo bench";
    build = "${rust}/bin/cargo build";
    check = "${rust}/bin/cargo clippy --tests --benches";
    doc = "${rust}/bin/cargo doc";
    fmt = "${rust}/bin/cargo fmt";
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

  # Package creation
  createPackages = mapAttrs (name: cmd: script name cmd);

  rustPackages = pkgs.symlinkJoin {
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

  # Shell completion
  proxyCompletion = ''
        _${options.name}_complete() {
    local cur prev opts cmds

          COMPREPLY=()
          cur="$\{COMP_WORDS[COMP_CWORD]\}"
          prev="$\{COMP_WORDS[COMP_CWORD-1]\}"
          cmds="$(compgen -c | grep ^${options.name}- | sed 's/${options.name}-//')"

          if [ $COMP_CWORD -eq 1 ]; then
            COMPREPLY=( $(compgen -W "$cmds" -- $cur) )
          elif [ $COMP_CWORD -gt 1 ]; then
            cmd="$\{COMP_WORDS[1]\}"
            opts="$(${options.name}-$cmd --help 2>&1 | grep -oE '^\s*-[a-zA-Z0-9-]+' | tr '\n' ' ')"
            COMPREPLY=( $(compgen -W "$opts" -- $cur) )
    fi

    return 0

        }
        complete -F _${options.name}_complete ${options.name}
  '';

  # Main script
  mainScript = mkDerivation {
    name = "${options.name}-1.0.0";
    version = "1.0.0";
    src = ./scripts;
    nativeBuildInputs = [ pkgs.installShellFiles ];
    installPhase = ''
      install -D $src/proxy.sh $out/bin/${options.name}
      installShellCompletion --name ${options.name} --bash <(echo "${proxyCompletion}")
    '';
  };

  # Shell inputs
  shellInputs =
    [
      mainScript
      rust
    ]
    ++ (if rustPackages ? paths then rustPackages.paths else [ rustPackages ]) ++ options.dependencies;

in
{
  inherit
    utils
    shellInputs
    createRustPlatform
    buildRustPackage
    rust
    ;
  devShell = pkgs.mkShell (utils.deepMerge env { buildInputs = shellInputs; });
}
