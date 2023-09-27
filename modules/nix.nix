{ options, pkgs }:
let prefix = "${options.name}-nix";
in {
  scripts = [
    (pkgs.writeShellApplication {
      name = "${prefix}-update-input";
      text = ''${pkgs.nix}/bin/nix flake lock --update-input "$@"'';
    })
    (pkgs.writeShellApplication {
      name = "${prefix}-direnv-reload";
      text = ''${pkgs.direnv}/bin/direnv reload "$@"'';
    })
  ];
}
