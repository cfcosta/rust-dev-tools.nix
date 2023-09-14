{
  description = "Tooling for developing rust applications using nix";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    {
      setup = packageName: pkgs:
        import ./modules {
          inherit pkgs;
          inherit packageName;

          utils = import ./utils { inherit pkgs; };
        };
    } // flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        tools = self.outputs.setup "rust-dev-tools" pkgs;
      in {
        devShell = with pkgs;
          mkShell {
            packages = [
              (tools.database.fromDockerCompose ./docker-compose.example.yml
                "db")
            ];
          };
      });
}
