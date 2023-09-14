{
  description = "Tooling for developing rust applications using nix";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    let
      utils = pkgs: rec {
        readYAML = yaml:
          builtins.fromJSON (builtins.readFile (pkgs.runCommand "from-yaml" {
            inherit yaml;
            allowSubstitutes = false;
            preferLocalBuild = true;
          } ''
            ${pkgs.remarshal}/bin/remarshal -if yaml -i <(echo "$yaml") -of json -o $out
          ''));

        fromYAML = path: readYAML (builtins.readFile path);
      };
      modules = import modules { inherit utils; };
    in {
      setup = packageName: pkgs:
        import ./modules {
          inherit pkgs;
          inherit packageName;

          utils = utils pkgs;
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
