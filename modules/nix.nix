{ options, pkgs }: {
  scripts = [
    (pkgs.writeShellApplication {
      name = "${options.name}-nix-update-input";
      text = "nix flake lock --update-input $@";
    })
  ];
}
