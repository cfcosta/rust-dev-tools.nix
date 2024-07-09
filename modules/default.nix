{
  pkgs,
  utils,
  options,
}:
let
  modules.rust = import ./rust.nix { inherit options pkgs utils; };
  env = utils.deepMerge modules.rust.env options.env;

  proxyCompletion = ''
    _${options.name}_complete() {
        local cur prev opts
        COMPREPLY=()
        cur="$\{COMP_WORDS[COMP_CWORD]\}"
        prev="$\{COMP_WORDS[COMP_CWORD-1]\}"
        opts="$(compgen -c | grep ^${options.name}- | sed 's/${options.name}-//')"

        if [[ $cur == * ]]; then
            COMPREPLY=( $(compgen -W "$opts" -- $cur) )
            return 0
        fi
    }

    complete -F _${options.name}_complete ${options.name}
  '';

  mainScript = pkgs.stdenv.mkDerivation {
    name = "${options.name}-1.0.0";
    version = "1.0.0";

    src = ./scripts;
    nativeBuildInputs = [ pkgs.installShellFiles ];

    installPhase = ''
      install -D $src/proxy.sh $out/bin/${options.name}
      installShellCompletion --name ${options.name} --bash <(echo "${proxyCompletion}")
    '';
  };

  packagesToUse =
    [ mainScript ]
    ++ (if builtins.isFunction modules.rust.findRust then [ ] else [ modules.rust.findRust ])
    ++ (
      if modules.rust.packages ? paths then modules.rust.packages.paths else [ modules.rust.packages ]
    )
    ++ options.dependencies;

  # Test functions
  testEnv = pkgs.runCommand "test-env" { } ''
    ${builtins.concatStringsSep "\n" (
      builtins.attrValues (builtins.mapAttrs (name: value: "echo '${name}=${value}' >> $out") env)
    )}
  '';

  testMainScript = pkgs.runCommand "test-main-script" { } ''
    if [ -f ${mainScript}/bin/${options.name} ]; then
      echo "Main script exists" > $out
    else
      echo "Main script does not exist" > $out
      exit 1
    fi
  '';

  testPackagesToUse = pkgs.runCommand "test-packages-to-use" { } ''
    echo "${toString (builtins.length packagesToUse)} packages in packagesToUse" > $out
    ${builtins.concatStringsSep "\n" (
      map (
        p:
        if builtins.isAttrs p && p ? outPath then
          "echo '${p.name} exists' >> $out"
        else
          "echo 'Non-derivation package: ${builtins.typeOf p}' >> $out"
      ) packagesToUse
    )}
  '';
in
{
  inherit utils;

  devShell = pkgs.mkShell ({ packages = packagesToUse; } // env);

  createRustPlatform = modules.rust.createRustPlatform;

  # Tests
  tests = {
    inherit testEnv testMainScript testPackagesToUse;
  };
}
