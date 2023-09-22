{ pkgs }:
let
  readYAML = yaml:
    builtins.fromJSON (builtins.readFile (pkgs.runCommand "from-yaml" {
      inherit yaml;
      allowSubstitutes = false;
      preferLocalBuild = true;
    } ''
      ${pkgs.remarshal}/bin/remarshal -if yaml -i <(echo "$yaml") -of json -o $out
    ''));

  deepMerge = lhs: rhs:
    if rhs == null then
      lhs
    else if lhs == null then
      rhs
    else if builtins.isAttrs lhs && builtins.isAttrs rhs then
      builtins.foldl' (acc: key:
        acc // {
          ${key} = deepMerge (lhs.${key} or null) (rhs.${key} or null);
        }) lhs (builtins.attrNames rhs)
    else
      rhs;

  containsLibraries = pkg:
    let
      checkResult = pkgs.runCommand "check-has-libs" { } ''
        if test -d ${pkg.outPath}/lib; then
          echo "yes"
        else
          echo "no"
        fi > $out
      '';
    in builtins.readFile checkResult == "yes";
in {
  inherit deepMerge containsLibraries;

  fromYAML = path: readYAML (builtins.readFile path);
}
