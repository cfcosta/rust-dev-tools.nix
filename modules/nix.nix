{ options, pkgs }:
let prefix = "${options.name}-nix";
in {
  scripts = [
    (pkgs.writeShellApplication {
      name = "${prefix}-update-input";
      text = ''${pkgs.nix}/bin/nix flake lock --update-input "$@"'';
    })
  ];
}
