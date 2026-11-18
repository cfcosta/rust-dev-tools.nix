{ pkgs, self }:
let
  rdt = self.setup pkgs { name = "rdt-closure-probe"; };
  package = rdt.buildRustPackage { src = ./fixture; };
  closure = pkgs.closureInfo { rootPaths = [ package ]; };
in
{
  # The probe's panics name files in the vendored crates and in the
  # toolchain's rust-src; neither may stay in its runtime closure.
  testRuntimeClosure = pkgs.runCommand "test-runtime-closure" { } ''
    test "$(${package}/bin/rdt-closure-probe)" = 4
    for path in ${pkgs.lib.concatStringsSep " " package.passthru.buildOnly}; do
      if grep -qx "$path" ${closure}/store-paths; then
        echo "$path is in the runtime closure" >&2
        exit 1
      fi
    done
    touch "$out"
  '';
}
