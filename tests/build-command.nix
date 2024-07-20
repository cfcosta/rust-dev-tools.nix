{ pkgs, runCommand }:

let
  rdt = pkgs.rust-dev-tools.setup {
    name = "rdt-example";
    dependencies = with pkgs; [ openssl ];
  };

  package = rdt.buildRustPackage {
    src = ../example;
    cargoLock.lockFile = ../example/Cargo.lock;
  };
in
runCommand "test-build-command"
  {
    buildInputs = [
      rdt.shellInputs
      package
    ];
  }
  ''
    cp -rf ${../example} $out
    cd $out
    rdt-example fmt
  ''
