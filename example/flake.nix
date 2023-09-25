{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs";
    flake-utils.url = "github:numtide/flake-utils";
    rust-dev-tools.url = "github:cfcosta/rust-dev-tools.nix";
  };

  outputs = inputs@{ self, nixpkgs, flake-utils, rust-dev-tools }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        tools = rust-dev-tools.setup system (pkgs: {
          name = "example";
          cargoToml = ./Cargo.toml;
          cargoConfig = ./.cargo/config;
          dependencies = with pkgs; [ pkg-config openssl ];
          shell.onInit = ''
            echo "Hello from devShell!"
          '';
        });
      in { devShells.default = tools.devShell; });
}
