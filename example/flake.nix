{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs";
    flake-utils.url = "github:numtide/flake-utils";
    rust-dev-tools.url = "path:..";
  };

  outputs = inputs@{ self, nixpkgs, flake-utils, rust-dev-tools }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        tools = rust-dev-tools.setup {
          name = "example";

          inherit system;

          rust.cargoToml = ./Cargo.toml;
        };
      in { devShells.default = tools.devShell; });
}
