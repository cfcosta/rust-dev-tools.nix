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
        enableNightlyTools = false;
        overrides = {
          linux.useMold = true;
          darwin.useLLD = true;
        };
      };

      lib = {
        inherit version;

        setup =
          pkgs: overrides:
          let
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

      developmentEnv =
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ rust-overlay.overlays.default ];
          };
        in
        {
          devShells.default = pkgs.mkShell { packages = with pkgs; [ nixfmt-rfc-style ]; };

          checks =
            let
              inherit (pkgs.lib) optionalAttrs;
              inherit (pkgs.stdenv) isDarwin;

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
                pkgs.runCommand "test-build-rust-package" { } ''
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
              testStable = runCase { version = self.version.stable; };
              testNightly = runCase { version = self.version.nightly; };
              testFromToolchain = runCase { version = self.version.fromToolchain "nightly" "latest"; };
              testFromToolchainFile = runCase {
                version = self.version.fromToolchainFile ./example/rust-toolchain.toml;
              };
              testDarwinLLD = optionalAttrs isDarwin (runCase {
                overrides.darwin.useLLD = true;
              });
            };
        };
    in
    {
      inherit (lib) version setup;

      overlays.default = rust-overlay.overlays.default;
    }
    // flake-utils.lib.eachDefaultSystem developmentEnv;
}
