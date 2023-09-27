{ pkgs, utils, options }:
let
  modules.rust = import ./rust.nix { inherit options pkgs utils; };
  env = utils.deepMerge modules.rust.env options.env;
in {
  inherit utils;

  devShell = pkgs.mkShell ({
    inherit (options) shellHook;

    packages = [ (modules.rust.findRust) (modules.rust.packages) ]
      ++ options.dependencies;
  } // env);
}
