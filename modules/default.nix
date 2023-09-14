{ packageName, pkgs, utils, inputs }: {
  inherit utils;

  overlays.default = [ inputs.rust-overlay.overlays.default ];

  database = import ./database.nix { inherit packageName pkgs utils; };
  rust = import ./rust.nix { inherit packageName pkgs utils; };
}
