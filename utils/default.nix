{ pkgs }:
let
  readYAML = yaml:
    builtins.fromJSON (builtins.readFile (pkgs.runCommand "from-yaml" {
      inherit yaml;
      allowSubstitutes = false;
      preferLocalBuild = true;
    } ''
      ${pkgs.remarshal}/bin/remarshal -if yaml -i <(echo "$yaml") -of json -o $out
    ''));
in { fromYAML = path: readYAML (builtins.readFile path); }
