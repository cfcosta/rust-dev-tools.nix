{ pkgs, utils, options }:
let
  modules = { rust = import ./rust.nix { inherit options pkgs utils; }; };

  env = utils.deepMerge modules.rust.env options.env;
in {
  inherit utils;

  devShell = pkgs.mkShell ({
    packages = [ (modules.rust.findRust) (modules.rust.packages) ]
      ++ options.dependencies;
    shellHook = if options.shellHook == null then "" else options.shellHook;
  } // env);
}
