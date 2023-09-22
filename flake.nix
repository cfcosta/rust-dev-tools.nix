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
      setup = options:
        import ./modules rec {
          inherit options;
          inherit inputs;

          pkgs = import nixpkgs {
            inherit (options) system;
            overlays = [ rust-overlay.overlays.default ];
          };

          utils = import ./utils { inherit pkgs; };
        };
    } // flake-utils.lib.eachDefaultSystem (system:
      let pkgs = import nixpkgs { inherit system; };
      in {
        devShells.default = with pkgs; mkShell { packages = [ nixfmt ]; };
      });
}
