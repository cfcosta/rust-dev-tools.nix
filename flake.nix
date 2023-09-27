{
  description = "Tooling for developing rust applications using nix";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs";
    flake-utils.url = "github:numtide/flake-utils";

    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.flake-utils.follows = "flake-utils";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ self, nixpkgs, flake-utils, rust-overlay }:
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

        fromCargoToml = file: {
          inherit file;
          source = "cargo";
        };
      };
    in {
      inherit version;

      setup = system: overrides:
        let
          defaultOptions = {
            cargoConfig = null;
            dependencies = [ ];
            env = { };
            rust = version.fromToolchain "stable" "latest";
            shellHook = null;
            overrides = {
              linux.useMold = true;
              darwin.useLLD = true;
            };
          };
        in import ./modules rec {
          utils = import ./utils { inherit pkgs; };
          options = utils.deepMerge defaultOptions (overrides pkgs);

          pkgs = import nixpkgs {
            inherit system;
            overlays = [ rust-overlay.overlays.default ];
          };
        };
    } // flake-utils.lib.eachDefaultSystem (system:
      let pkgs = import nixpkgs { inherit system; };
      in {
        devShells.default = with pkgs; mkShell { packages = [ nixfmt ]; };
      });
}
