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
      overlay =
        final: prev:
        let
          inherit (final.lib) mkDefault makeExtensible;

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

            fromCargoToml = file: {
              inherit file;
              source = "cargo";
            };
          };

          defaultOptions = {
            name = "dev";
            cargoConfig = null;
            dependencies = [ ];
            env = { };
            rust = mkDefault (version.fromToolchain "stable" "latest");
            overrides = {
              linux.useMold = true;
              darwin.useLLD = true;
            };
          };

          makeSetup =
            {
              pkgs,
              utils,
              options,
            }:
            import ./. { inherit pkgs utils options; };

          rust-dev-tools = makeExtensible (self: {
            inherit version defaultOptions;

            setup =
              overrides:
              let
                utils = import ./utils { pkgs = final; };
                options = utils.deepMerge defaultOptions overrides;
                modules = makeSetup {
                  pkgs = final;
                  inherit utils options;
                };
                inherit (modules) shellInputs;
                devShell = final.mkShell {
                  inputsFrom = [ shellInputs ];
                  buildInputs = [ ];
                };
              in
              {
                inherit devShell shellInputs;
                inherit (modules) rust createRustPlatform buildRustPackage;
              };
          });
        in
        {
          inherit rust-dev-tools;
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
            in
            {
              testBuildRustPackage = pkgs.callPackage ./tests/build-rust-package.nix { };
              testStable = pkgs.callPackage ./tests/stable.nix { };
              testNightly = pkgs.callPackage ./tests/nightly.nix { };
              testFromToolchain = pkgs.callPackage ./tests/from-toolchain.nix { };
              testFromToolchainFile = pkgs.callPackage ./tests/from-toolchain-file.nix { };
              testRustPackage = pkgs.callPackage ./tests/rust-package.nix { };
              testBuildCommand = pkgs.callPackage ./tests/build-command.nix { };
            };
        };
    in
    {
      overlays.default = nixpkgs.lib.composeExtensions rust-overlay.overlays.default overlay;
    }
    // flake-utils.lib.eachDefaultSystem developmentEnv;
}
