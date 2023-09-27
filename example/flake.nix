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
          rust = rust-dev-tools.version.fromToolchainFile ./rust-toolchain.toml;
          dependencies = with pkgs; [ pkg-config openssl ];
          shellHook = ''
            echo "Hello from devShell!"
          '';
        });
      in { devShells.default = tools.devShell; });
}
