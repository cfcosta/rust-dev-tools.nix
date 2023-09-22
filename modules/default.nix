{ pkgs, utils, inputs, options }:
let
  tools = {
    database = import ./database.nix { inherit options pkgs utils; };
    rust = import ./rust.nix { inherit options pkgs utils; };
    nix = import ./nix.nix { inherit options pkgs; };
  };
in {
  inherit utils;

  devShell = pkgs.mkShell {
    packages = [ (tools.rust.package.fromCargo options.rust.cargoToml) ];
  };
}
