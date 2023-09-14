{
  description = "Tooling for developing rust applications using nix";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs";
    flake-utils.url = "github:numtide/flake-utils";
    rust-overlay.url = "github:oxalica/rust-overlay";
  };

  outputs = inputs@{ self, nixpkgs, flake-utils, rust-overlay }:
    {
      setup = packageName: pkgs:
        import ./modules {
          inherit pkgs;
          inherit packageName;
          inherit inputs;

          utils = import ./utils { inherit pkgs; };
        };
    } // flake-utils.lib.eachDefaultSystem (system:
      let pkgs = import nixpkgs { inherit system; };
      in { devShell = with pkgs; mkShell { packages = [ nixfmt ]; }; });
}
