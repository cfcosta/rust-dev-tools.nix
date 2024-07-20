{
  description = "Tooling for developing rust applications using nix";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs";
    flake-utils.url = "github:numtide/flake-utils";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      rust-overlay,
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
      };

      overlay = final: prev: {
        rust-dev-tools = {
          setup =
            overrides:
            let
              utils = import ./utils { pkgs = final; };

              modules = import ./. {
                pkgs = final;
                inherit utils;
                options = utils.deepMerge defaultOptions overrides;
              };

              inherit (modules) shellInputs;

              devShell = final.mkShell {
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
      };

      developmentEnv =
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [
              rust-overlay.overlays.default
              overlay
            ];
          };
        in
        {
          devShells.default = pkgs.mkShell { packages = with pkgs; [ nixfmt-rfc-style ]; };

          checks =
            let
              inherit (pkgs) runCommand;

              runCase =
                args:
                let
                  rdt = pkgs.rust-dev-tools.setup (
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
              testStable = runCase { version = version.stable; };
              testNightly = runCase { version = version.nightly; };
              testFromToolchain = runCase { version = version.fromToolchain "nightly" "latest"; };
              testFromToolchainFile = runCase {
                version = version.fromToolchainFile ./example/rust-toolchain.toml;
              };
              testRustPackage =
                let
                  rdt = pkgs.rust-dev-tools.setup {
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
                  rdt = pkgs.rust-dev-tools.setup {
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
            };
        };
    in
    {
      inherit (lib) version;

      overlays.default = nixpkgs.lib.composeExtensions rust-overlay.overlays.default overlay;
    }
    // flake-utils.lib.eachDefaultSystem developmentEnv;
}
