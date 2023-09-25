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
    {
      setup = system: overrides:
        let
          defaultOptions = {
            dependencies = [ ];
            cargoToml = null;
            cargoConfig = null;
            shell = {
              env = { };
              onInit = null;
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
