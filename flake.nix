{
  description = "Tooling for developing rust applications using nix";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs";
  };

  outputs =
    {
      self,
      nixpkgs,
      ...
    }:
    let
      version = rec {
        stable = fromToolchain "stable" "latest";
        nightly = fromToolchain "nightly" "latest";

        fromToolchain = channel: version: {
          inherit channel version;
          source = "toolchain";
        };

        fromToolchainFile = file: {
          inherit file;
          source = "toolchainFile";
        };
        fromRustToolchainFile = fromToolchainFile;
        fromRustupToolchainFile = fromToolchainFile;

        fromCargoToml = file: {
          inherit file;
          source = "cargo";
        };
        fromCargo = fromCargoToml;
      };

      defaultOptions = {
        name = "dev";
        cargoConfig = null;
        dependencies = [ ];
        env = { };
        rust = version.fromToolchain "stable" "latest";
        overrides = {
          linux.useMold = true;
          darwin.useLLD = true;
        };
      };

      lib = {
        inherit version;

        # rustfmt and cargo-fmt alone, for a formatter outside a toolchain.
        rustfmt = pkgs: rust: import ./rust-toolchain { inherit pkgs; } (rust // { formatterOnly = true; });

        setup =
          pkgs: overrides:
          let
            utils = import ./utils { inherit pkgs; };

            modules = import ./. {
              inherit pkgs utils;
              options = utils.deepMerge defaultOptions overrides;
            };

            inherit (modules) shellInputs;

            devShell = pkgs.mkShell {
              inputsFrom = [ shellInputs ];
              buildInputs = [ ];
            };
          in
          {
            inherit devShell shellInputs;
            inherit (modules) rust;

            createRustPlatform = modules.createRustPlatform;
            buildRustPackage = modules.buildRustPackage;
          };
      };

      developmentEnv =
        system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        {
          devShells.default = pkgs.mkShell { packages = with pkgs; [ nixfmt-rfc-style ]; };

          # Writes the unit plan of the flake in the current directory.
          apps.plan = {
            type = "app";
            program = "${
              pkgs.writeShellApplication {
                name = "rdt-plan";
                runtimeInputs = with pkgs; [
                  jq
                  python3
                ];
                text = ''
                  export RDT_PLANNER=${./rust-cache/plan-units.py}
                  exec bash ${./scripts/plan-units.sh} "$@"
                '';
              }
            }/bin/rdt-plan";
          };

          checks =
            let
              inherit (pkgs) runCommand;

              runCase =
                args:
                let
                  rdt = self.setup pkgs (
                    args
                    // {
                      name = "rdt-example";
                      dependencies = with pkgs; [ openssl ];
                    }
                  );

                  package = rdt.buildRustPackage {
                    src = ./example;
                    cargoLock.lockFile = ./example/Cargo.lock;
                  };
                in
                runCommand "test-build-rust-package" { } ''
                  if [ ! -e ${package}/bin/rdt-example ]; then
                    echo "Error: Built package does not contain the expected binary"
                    exit 1
                  fi

                  ${package}/bin/rdt-example

                  touch $out
                '';
            in
            {
              testBuildRustPackage = runCase { };
              testExplicitLockfileContext = import ./checks/lockfile-context { inherit pkgs self; };
              testStable = runCase { rust = self.version.stable; };
              testNightly = runCase { rust = self.version.nightly; };
              testFromToolchainFile = runCase {
                rust = self.version.fromToolchainFile ./example/rust-toolchain.toml;
              };
              testRustPackage =
                let
                  rdt = self.setup pkgs {
                    name = "rdt-example";
                    dependencies = with pkgs; [ openssl ];
                  };
                in
                runCommand "test-rust-package" { } ''
                  if [ ! -e ${rdt.rust}/bin/rustc ]; then
                    echo "Error: Rust package does not contain the expected rustc binary"
                    exit 1
                  fi

                  ${rdt.rust}/bin/rustc --version

                  touch $out
                '';
              testBuildCommand =
                let
                  rdt = self.setup pkgs {
                    name = "rdt-example";
                    dependencies = with pkgs; [ openssl ];
                  };

                  package = rdt.buildRustPackage {
                    src = ./example;
                    cargoLock.lockFile = ./example/Cargo.lock;
                  };
                in
                runCommand "test-build-command"
                  {
                    buildInputs = [
                      rdt.shellInputs
                      package
                    ];
                  }
                  ''
                    cp -rf ${./example} $out
                    cd $out
                    rdt-example fmt
                  '';
            }
            // import ./tests { inherit pkgs self; }
            // import ./checks/build-shapes { inherit pkgs self; }
            // import ./checks/toolchains { inherit pkgs self; }
            // import ./checks/runtime-closure { inherit pkgs self; }
            // import ./checks/dependency-layers { inherit pkgs self; }
            // import ./checks/unit-plan { inherit pkgs self; };
        };

      perSystem = nixpkgs.lib.genAttrs [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ] developmentEnv;
    in
    {
      inherit (lib) version setup rustfmt;

      checks = builtins.mapAttrs (_: env: env.checks) perSystem;
      apps = builtins.mapAttrs (_: env: env.apps) perSystem;
      devShells = builtins.mapAttrs (_: env: env.devShells) perSystem;
    };
}
