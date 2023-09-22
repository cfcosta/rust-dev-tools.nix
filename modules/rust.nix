{ pkgs, utils, options }:
with pkgs.lib;
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
    (pkgs.writeShellScriptBin "${options.name}-${name}" cmd)
    (pkgs.writeShellScriptBin "${options.name}-watch-${name}"
      (watch "${options.name}-${name}"))
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

  systemSpecificDependencies = with pkgs; rec {
    aarch64-darwin = [ darwin.apple_sdk.frameworks.SystemConfiguration ];
    x86_64-darwin = aarch64-darwin;

    x86_64-linux = optionals options.rust.useMold [ mold ];
    aarch64-linux = x86_64-linux;
  };

  systemFlags = with pkgs; rec {
    x86_64-darwin = [ ];
    aarch64-darwin = x86_64-darwin;

    x86_64-linux =
      optionals options.rust.useMold [ "-C link-arg=-fuse-ld=mold" ];
    aarch64-linux = x86_64-linux;
  };

  depsWithLibs = builtins.filter utils.containsLibraries options.dependencies;
in {
  fromCargo = file:
    let
      toml = builtins.fromTOML (builtins.readFile file);

      version = if builtins.hasAttr "package" toml
      && builtins.hasAttr "rust-version" toml.package then
        toml.package.rust-version
      else
        "latest";
    in rust "stable" version;

  env = {
    RUSTFLAGS = concatStringsSep " " (systemFlags.${pkgs.system});
    LD_LIBRARY_PATH =
      makeLibraryPath (depsWithLibs ++ [ pkgs.stdenv.cc.cc.lib ]);
  };

  packages = [
    (script "audit" audit)
    (script "bench" bench)
    (script "check" check)
    (script "doc" doc)
    (script "fmt" fmt)
    (script "test" test)

    (nightlyScript "udeps" udeps)
  ] ++ systemSpecificDependencies."${pkgs.system}";
}
