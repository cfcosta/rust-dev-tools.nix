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
  nightlyScript = name: cmd:
    script name ''
      export RUSTC="${rustNightly}/bin/rustc";
      export CARGO="${rustNightly}/bin/cargo";

      ${cmd}
    '';

  audit = "exec ${pkgs.cargo-audit}/bin/cargo-audit audit $@";
  bench = "exec cargo bench $@";
  check = "exec cargo clippy --tests --benches $@";
  doc = "exec cargo doc $@";
  fmt = "exec cargo fmt $@";
  test = "exec ${pkgs.cargo-nextest}/bin/cargo-nextest nextest run";
  udeps = "exec ${pkgs.cargo-udeps}/bin/cargo-udeps udeps $@";
in {
  package = {
    latest = rust "stable" "latest";
    latestNightly = rustNightly;

    stable = version: rust "stable" version;
    nightly = date: rust "nightly" date;
  };

  scripts = [
    (script "audit" audit)
    (script "bench" bench)
    (script "check" check)
    (script "doc" doc)
    (script "fmt" fmt)
    (script "test" test)

    (nightlyScript "udeps" udeps)
  ];
}
