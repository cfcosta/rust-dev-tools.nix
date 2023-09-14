{ pkgs, utils, packageName }:
let
  rust = channel: version:
    pkgs.rust-bin.${channel}.${version}.default.override {
      extensions = [ "rust-src" "clippy" "rustfmt" "rust-analyzer" ];
    };
  rustNightly = rust "nightly" "latest";

  watch = cmd: ''
    ${pkgs.cargo-watch}/bin/cargo-watch watch -s "${cmd}"
  '';

  script = name: cmd: [
    (pkgs.writeShellScriptBin "${packageName}-${name}" cmd)
    (pkgs.writeShellScriptBin "${packageName}-watch-${name}"
      (watch "${packageName}-${name}"))
  ];

  audit = "exec ${pkgs.cargo-audit}/bin/cargo-audit audit $@";
  bench = "exec cargo bench $@";
  check = "exec cargo clippy --tests --benches $@";
  doc = "exec cargo doc $@";
  fmt = "exec cargo fmt $@";
  test = "exec ${pkgs.cargo-nextest}/bin/cargo-nextest nextest run";

  # Nightly-only tools
  udeps = ''
    export RUSTC="${rustNightly}/bin/rustc";
    export CARGO="${rustNightly}/bin/cargo";
    exec "${pkgs.cargo-udeps}/bin/cargo-udeps" udeps $@
  '';
in {
  package = {
    latest = rust "stable" "latest";
    stable = version: rust "stable" version;
  };

  scripts = [
    (script "audit" audit)
    (script "bench" bench)
    (script "check" check)
    (script "doc" doc)
    (script "fmt" fmt)
    (script "test" test)
    (script "udeps" udeps)
  ];
}
