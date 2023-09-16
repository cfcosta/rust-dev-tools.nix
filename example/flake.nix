{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs";
    flake-utils.url = "github:numtide/flake-utils";
    rust-dev-tools.url = "path:..";
  };

  outputs = inputs@{ self, nixpkgs, flake-utils, rust-dev-tools }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        tools = rust-dev-tools.setup "example" pkgs;

        pkgs = import nixpkgs {
          inherit system;
          overlays = tools.overlays.default;
        };
      in {
        devShell = with pkgs;
          mkShell {
            packages = [
              (tools.rust.package.fromCargo ./Cargo.toml)

              (tools.nix.scripts)
              (tools.rust.scripts)

              (tools.database.fromDockerCompose ./docker-compose.yml "db")
            ];
          };
      });
}
