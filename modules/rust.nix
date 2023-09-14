{ pkgs, utils, packageName }:
let
  rust = channel: version:
    pkgs.rust-bin.${channel}.${version}.default.override {
      extensions = [ "rust-src" "clippy" "rustfmt" "rust-analyzer" ];
    };

  watch = cmd: ''
    ${pkgs.cargo-watch}/bin/cargo-watch watch -s "${cmd}"
  '';

  script = name: cmd: [
    (pkgs.writeShellScriptBin "${packageName}-${name}" cmd)
    (pkgs.writeShellScriptBin "${packageName}-watch-${name}"
      (watch "${packageName}-${name}"))
  ];

  check = "cargo clippy --tests --benches $@";
  test = "${pkgs.cargo-nextest}/bin/cargo-nextest nextest run --release";
  bench = "cargo bench $@";
  doc = "cargo doc";
in {
  package = {
    latest = rust "stable" "latest";
    stable = version: rust "stable" version;
  };

  scripts = [
    (script "check" check)
    (script "test" test)
    (script "bench" bench)
    (script "doc" doc)
  ];
}
