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

  outputs = { nixpkgs, flake-utils, rust-overlay, ... }:
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
    in {
      inherit version;

      overlays.default = rust-overlay.overlays.default;

      setup = pkgs: overrides:
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
        in {
          devShell = modules.devShell;
          createRustPlatform = modules.createRustPlatform;
          findRust = modules.rust.findRust;
        };

    } // flake-utils.lib.eachDefaultSystem (system:
      let pkgs = import nixpkgs { inherit system; };
      in {
        devShells.default = with pkgs; mkShell { packages = [ nixfmt-rfc-style ]; };
      });
}