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
      let
        tools = self.outputs.setup "rdt" pkgs;

        pkgs = import nixpkgs {
          inherit system;

          overlays = tools.overlays.default;
        };
      in {
        devShell = with pkgs;
          mkShell {
            packages = [
              (tools.rust.package.latest)
              (tools.rust.scripts)
              (tools.database.fromDockerCompose ./docker-compose.example.yml
                "db")
            ];
          };
      });
}
