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
                darwin.useLLD = true;
              };
            };
            modules = import ./modules rec {
              inherit pkgs;
              utils = import ./utils { inherit pkgs; };
              options = utils.deepMerge defaultOptions overrides;
            };
          in
          {
            devShell = modules.devShell;
            createRustPlatform = modules.createRustPlatform;
            findRust = modules.rust.findRust;
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
              darwin.useLLD = true;
            };
          };
        };
      in
      {
        devShells.default = mkShell { packages = with pkgs; [ nixfmt-rfc-style ]; };

        # Add tests to ensure the setup and devShell work correctly
        checks = {
          testSetup =
            let
              rdt = self.lib.setup pkgs {
                name = "test-project";
                dependencies = with pkgs; [ openssl ];
              };
            in
            pkgs.mkShell {
              inputsFrom = [ rdt.devShell ];
              shellHook = ''
                echo "Test setup shell initialized"
              '';
            };

          testRustPlatform =
            let
              rustPlatform = (self.lib.setup pkgs { }).createRustPlatform { };
            in
            rustPlatform.buildRustPackage {
              pname = "test-package";
              version = "0.1.0";
              src = ./example;
              cargoLock.lockFile = ./example/Cargo.lock;
            };
        } // builtins.mapAttrs (name: value: value) modules.tests;
      }
    );
}
