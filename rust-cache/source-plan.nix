{ lib }:
src:
let
  root = toString src;
  # Record names and manifest/config contents, never local Rust source contents.
  walk =
    dir: prefix:
    let
      entries = builtins.readDir dir;
    in
    lib.concatMap (
      name:
      let
        path = dir + "/${name}";
        relative = prefix + name;
        kind = entries.${name};
      in
      if
        kind == "directory"
        && !(builtins.elem name [
          ".git"
          "target"
        ])
      then
        walk path (relative + "/")
      else if kind == "regular" then
        [ relative ]
      else if kind == "symlink" then
        throw "buildRustPackage: symlinks inside Cargo sources are not supported by dependency-source planning: ${relative}"
      else
        [ ]
    ) (builtins.attrNames entries);
  files = walk root "";
  read = path: builtins.unsafeDiscardStringContext (builtins.readFile (root + "/${path}"));
  manifests = builtins.filter (path: builtins.baseNameOf path == "Cargo.toml") files;
  configs = builtins.filter (
    path:
    lib.hasSuffix "/.cargo/config" ("/" + path) || lib.hasSuffix "/.cargo/config.toml" ("/" + path)
  ) files;
  rustFiles = builtins.filter (lib.hasSuffix ".rs") files;
  manifestData = builtins.listToAttrs (
    map (path: {
      name = path;
      value = builtins.fromTOML (read path);
    }) manifests
  );
in
assert lib.assertMsg (builtins.elem "Cargo.toml" manifests)
  "buildRustPackage: src must contain a root Cargo.toml";
{
  manifests = manifestData;
  configs = builtins.listToAttrs (
    map (path: {
      name = path;
      value = read path;
    }) configs
  );
  inherit rustFiles;
}
