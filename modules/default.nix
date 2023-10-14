{ pkgs, utils, options }:
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
in {
  inherit utils;

  devShell = pkgs.mkShell ({
    inherit (options) shellHook;

    packages = [ mainScript modules.rust.findRust modules.rust.packages ]
      ++ options.dependencies;
  } // env);
}
