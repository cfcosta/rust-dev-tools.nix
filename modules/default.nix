{
  pkgs,
  utils,
  options,
}:
let
  inherit (pkgs.stdenv) mkDerivation;
  inherit (pkgs) runCommand;
  inherit (builtins)
    attrValues
    concatStringsSep
    isAttrs
    isFunction
    mapAttrs
    typeOf
    ;

  modules.rust = import ./rust.nix { inherit options pkgs utils; };
  env = utils.deepMerge modules.rust.env options.env;

  proxyCompletion = ''
    _${options.name}_complete() {
      local cur prev opts cmds

      COMPREPLY=()
      cur="$\{COMP_WORDS[COMP_CWORD]\}"
      prev="$\{COMP_WORDS[COMP_CWORD-1]\}"
      cmds="$(compgen -c | grep ^${options.name}- | sed 's/${options.name}-//')"

      if [ $COMP_CWORD -eq 1 ]; then
        COMPREPLY=( $(compgen -W "$cmds" -- $cur) )
      elif [ $COMP_CWORD -gt 1 ]; then
        cmd="$\{COMP_WORDS[1]\}"
        opts="$(${options.name}-$cmd --help 2>&1 | grep -oE '^\s*-[a-zA-Z0-9-]+' | tr '\n' ' ')"
        COMPREPLY=( $(compgen -W "$opts" -- $cur) )
fi

return 0

    }

    complete -F _${options.name}_complete ${options.name}
  '';

  mainScript = mkDerivation {
    name = "${options.name}-1.0.0";
    version = "1.0.0";

    src = ./scripts;
    nativeBuildInputs = [ pkgs.installShellFiles ];

    installPhase = ''
      install -D $src/proxy.sh $out/bin/${options.name}
      installShellCompletion --name ${options.name} --bash <(echo "${proxyCompletion}")
    '';
  };

  rustEnv = modules.rust.findRust options.rust;

  packagesToUse =
    [ mainScript ]
    ++ [ rustEnv.rustPackage ]
    ++ (
      if modules.rust.packages ? paths then modules.rust.packages.paths else [ modules.rust.packages ]
    )
    ++ options.dependencies;

  # Test functions
  testEnv = runCommand "test-env" { } ''
    ${concatStringsSep "\n" (
      attrValues (mapAttrs (name: value: "echo '${name}=${value}' >> $out") env)
    )}
  '';

  testMainScript = runCommand "test-main-script" { } ''
    if [ -f ${mainScript}/bin/${options.name} ]; then
      echo "Main script exists" > $out
    else
      echo "Main script does not exist" > $out
      exit 1
    fi
  '';

  testPackagesToUse = runCommand "test-packages-to-use" { } ''
    echo "${toString (builtins.length packagesToUse)} packages in packagesToUse" > $out
    ${concatStringsSep "\n" (
      map (
        p:
        if isAttrs p && p ? outPath then
          "echo '${p.name} exists' >> $out"
        else
"echo 'Non-derivation package: ${typeOf p}' >> $out"

      ) packagesToUse
    )}
  '';
in
{
  inherit utils;
  inherit (modules.rust) createRustPlatform buildRustPackage;

  devShell = pkgs.mkShell (env // { buildInputs = packagesToUse; });
  # Tests
  tests = {
    inherit testEnv testMainScript testPackagesToUse;
  };
}