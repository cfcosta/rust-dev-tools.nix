{ packageName, pkgs }: {
  scripts = [
    (pkgs.writeShellScriptBin "${packageName}-nix-update-input"
      "nix flake lock --update-input $@")
  ];
}
