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

      lib = {
        inherit version;

        setup =
          pkgs: overrides:
          let
            defaultOptions = {
              cargoConfig = null;
              dependencies = [ ];
              env = { };
              rust = version.fromToolchain "stable" "latest";
              enableNightlyTools = false;
              overrides = {
                linux.useMold = true;
                darwin.useLLD = false;
              };
            };
            modules = import ./modules rec {
              inherit pkgs;
              utils = import ./utils { inherit pkgs; };
              options = utils.deepMerge defaultOptions overrides;
            };

            devShell = pkgs.mkShell {
              inputsFrom = [ modules.devShell ];
              buildInputs = [ ];
            };
          in
          {
            inherit devShell;
            createRustPlatform = modules.createRustPlatform;
            buildRustPackage = modules.buildRustPackage;
          };
      };
    in
    {
      inherit lib;

      overlays.default = rust-overlay.overlays.default;
    }
    // flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ rust-overlay.overlays.default ];
        };

        inherit (pkgs) mkShell;

        modules = import ./modules {
          inherit pkgs;
          utils = import ./utils { inherit pkgs; };
          options = {
            name = "dev";
            cargoConfig = null;
            dependencies = [ ];
            env = { };
            rust = version.fromToolchain "stable" "latest";
            enableNightlyTools = false;
            overrides = {
              linux.useMold = true;
              darwin.useLLD = false;
            };
          };
        };
      in
      {
        devShells.default = mkShell { packages = with pkgs; [ nixfmt-rfc-style ]; };

        checks = {
          testBuildRustPackage =
            let
              rdt = self.lib.setup pkgs {
                name = "rdt-example";
                dependencies = with pkgs; [ openssl ];
              };

              builtPackage = rdt.buildRustPackage {
                version = "0.1.0";
                src = ./example;
                cargoLock.lockFile = ./example/Cargo.lock;
              };
            in
            pkgs.runCommand "test-build-rust-package" { } ''
              if [ ! -e ${builtPackage}/bin/rdt-example ]; then
                echo "Error: Built package does not contain the expected binary"
                exit 1
              fi

              ${builtPackage}/bin/rdt-example

              touch $out
            '';
        } // builtins.mapAttrs (_: value: value) modules.tests;
      }
    );
}
