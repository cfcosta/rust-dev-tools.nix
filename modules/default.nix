{ pkgs, utils, options }:
let
  modules = {
    rust = import ./rust.nix { inherit options pkgs utils; };
    nix = import ./nix.nix { inherit options pkgs; };
  };

  env = utils.deepMerge modules.rust.env options.shell.env;
in {
  inherit utils;

  devShell = pkgs.mkShell ({
    packages =
      [ (modules.nix.scripts) (modules.rust.fromCargo) (modules.rust.packages) ]
      ++ options.dependencies;
  } // env);
}
