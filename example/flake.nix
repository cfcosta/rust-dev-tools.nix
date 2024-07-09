{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs";
    flake-utils.url = "github:numtide/flake-utils";
    rust-dev-tools.url = "path:..";
  };

  outputs = { nixpkgs, flake-utils, rust-dev-tools, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ rust-dev-tools.overlays.default ];
        };

        rdt = rust-dev-tools.setup pkgs {
          name = "example";
          dependencies = with pkgs; [ openssl ];
        };

        rustPlatform = rdt.createRustPlatform rdt.findRust;
      in {
        devShells.default = pkgs.mkShell { inputsFrom = [ rdt.devShell ]; };
        inherit rustPlatform;
      });
}