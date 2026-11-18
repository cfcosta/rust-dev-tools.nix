{ pkgs }:

# Rust toolchains from the official release manifests on
# static.rust-lang.org.
#
# `manifests.json` holds one sha256 per dated release manifest, refreshed
# by `scripts/update-rust-manifests.sh`. The selected manifest is fetched
# at evaluation time, and its per-component URLs and hashes become
# ordinary fixed-output fetches.

let
  inherit (builtins)
    attrNames
    fetchurl
    filter
    fromTOML
    hasAttr
    head
    match
    readFile
    ;
  inherit (pkgs) lib stdenv;
  inherit (lib)
    hasPrefix
    last
    optionals
    sort
    trim
    unique
    versionOlder
    ;

  index = lib.importJSON ./manifests.json;
  dist = "https://static.rust-lang.org/dist";
  host = stdenv.hostPlatform.rust.rustcTarget;

  refresh = "Run scripts/update-rust-manifests.sh in rust-dev-tools.nix to index newer releases.";

  newestStable = last (sort versionOlder (attrNames index.stable));
  newestDate = channel: last (sort (a: b: a < b) (attrNames index.${channel}));

  # "1.85.0" names one release; "1.85" names the newest patch of 1.85.
  stableVersion =
    version:
    if version == "latest" then
      newestStable
    else if hasAttr version index.stable then
      version
    else
      let
        patches = filter (v: hasPrefix "${version}." v) (attrNames index.stable);
      in
      if patches == [ ] then
        throw "Rust ${version} is not in the manifest index. ${refresh}"
      else
        last (sort versionOlder patches);

  # A stable release published on `date`, for `stable-YYYY-MM-DD`.
  stableOn =
    date:
    let
      found = filter (v: index.stable.${v}.date == date) (attrNames index.stable);
    in
    if found == [ ] then throw "No stable Rust release is dated ${date}." else head found;

  # The manifest for one channel and version: `latest`, a release number
  # for stable, or a YYYY-MM-DD date for beta and nightly.
  release =
    channel: version:
    if channel == "stable" then
      let
        v = stableVersion version;
        entry = index.stable.${v};
      in
      {
        label = v;
        url = "${dist}/${entry.date}/channel-rust-${v}.toml";
        inherit (entry) sha256;
      }
    else if channel == "beta" || channel == "nightly" then
      let
        date = if version == "latest" then newestDate channel else version;
      in
      if hasAttr date index.${channel} then
        {
          label = "${channel}-${date}";
          url = "${dist}/${date}/channel-rust-${channel}.toml";
          sha256 = index.${channel}.${date};
        }
      else
        throw "No Rust ${channel} for ${date} in the manifest index. ${refresh}"
    else
      throw "Unknown Rust channel `${channel}`; expected stable, beta, or nightly.";

  # A rustup channel string: stable, beta, nightly, 1.85, 1.85.0, or any of
  # the three channels followed by -YYYY-MM-DD.
  parseChannel =
    text:
    let
      dated = match "(stable|beta|nightly)-([0-9]{4}-[0-9]{2}-[0-9]{2})" text;
    in
    if text == "stable" || text == "beta" || text == "nightly" then
      {
        channel = text;
        version = "latest";
      }
    else if dated != null then
      let
        channel = head dated;
        date = last dated;
      in
      if channel == "stable" then
        {
          inherit channel;
          version = stableOn date;
        }
      else
        {
          inherit channel;
          version = date;
        }
    else if match "[0-9]+\\.[0-9]+(\\.[0-9]+)?" text != null then
      {
        channel = "stable";
        version = text;
      }
    else
      throw "Unsupported Rust toolchain channel `${text}`.";

  # rust-toolchain.toml, or the legacy rust-toolchain file holding only a
  # channel name.
  fromToolchainFile =
    file:
    let
      text = trim (readFile file);
    in
    if match ".*=.*" (lib.replaceStrings [ "\n" ] [ " " ] text) == null then
      parseChannel text
    else
      let
        toolchain = (fromTOML text).toolchain or { };
      in
      parseChannel (toolchain.channel or "stable")
      // {
        components = toolchain.components or [ ];
        targets = toolchain.targets or [ ];
        profile = toolchain.profile or "default";
      };

  # Cargo.toml's rust-version, from the package or the workspace.
  fromCargoToml =
    file:
    let
      toml = fromTOML (readFile file);
      version = toml.package.rust-version or toml.workspace.package.rust-version or null;
    in
    if version == null || !(builtins.isString version) then
      throw "${toString file} sets no rust-version."
    else
      {
        channel = "stable";
        inherit version;
      };

  selection =
    options:
    let
      base =
        if options.source == "toolchainFile" then
          fromToolchainFile options.file
        else if options.source == "cargo" then
          fromCargoToml options.file
        else
          { inherit (options) channel version; };
    in
    {
      components = [ ];
      targets = [ ];
      profile = "default";
    }
    // base
    // {
      components = (base.components or [ ]) ++ (options.components or [ ]);
      targets = (base.targets or [ ]) ++ (options.targets or [ ]);
      profile = options.profile or base.profile or "default";
    };

  required = [
    "rustc"
    "cargo"
    "rust-std"
  ];

  # Added when the release ships them for the host.
  development = [
    "clippy"
    "rustfmt"
    "rust-analyzer"
    "rust-src"
  ];

  toolchain =
    options:
    let
      wanted = selection options;
      found = release wanted.channel wanted.version;
      manifest = fromTOML (
        readFile (fetchurl {
          inherit (found) url sha256;
        })
      );

      name = component: manifest.renames.${component}.to or component;

      # The manifest entry for `component` on `target`, or null when the
      # release does not ship it there.
      entry =
        component: target:
        let
          targets = manifest.pkg.${name component}.target or { };
          candidate = targets.${target} or targets."*" or null;
        in
        if candidate != null && (candidate.available or false) then candidate else null;

      need =
        component: target:
        let
          found' = entry component target;
        in
        if found' == null then throw "Rust ${found.label} has no ${component} for ${target}." else found';

      # With `rustfmt` taken from another toolchain, this one ships none, so
      # cargo cannot find a second cargo-fmt beside itself.
      hostComponents =
        filter (c: !(options.withoutRustfmt or false) || name c != "rustfmt-preview" && c != "rustfmt")
          (
            required
            ++ optionals (wanted.profile != "minimal") (filter (c: entry c host != null) development)
            ++ wanted.components
          );

      parts =
        map (component: need component host) (unique hostComponents)
        ++ map (target: need "rust-std" target) (filter (t: t != host) (unique wanted.targets));

      tarball =
        part:
        pkgs.fetchurl (
          if part ? xz_url then
            {
              url = part.xz_url;
              sha256 = part.xz_hash;
            }
          else
            {
              inherit (part) url;
              sha256 = part.hash;
            }
        );
    in
    stdenv.mkDerivation {
      pname = "rust-toolchain";
      version = found.label;

      srcs = map tarball parts;
      dontUnpack = true;
      dontConfigure = true;
      dontBuild = true;
      # rlibs and the compiler's own libraries must keep their symbols.
      dontStrip = true;

      nativeBuildInputs = optionals stdenv.hostPlatform.isLinux [ pkgs.autoPatchelfHook ];
      buildInputs = optionals stdenv.hostPlatform.isLinux [
        stdenv.cc.cc.lib
        pkgs.zlib
      ];

      # Each tarball lists its component directories in `components`; their
      # contents merge into one sysroot.
      installPhase = ''
        runHook preInstall
        mkdir -p "$out"
        for src in $srcs; do
          dir="$(mktemp -d)"
          tar -xf "$src" -C "$dir" --strip-components=1
          while read -r component; do
            cp -R "$dir/$component/." "$out/"
          done < "$dir/components"
          rm -f "$out/manifest.in"
          rm -rf "$dir"
        done
        runHook postInstall
      '';

      passthru = {
        inherit (found) label;
        inherit (wanted) channel;
        components = unique hostComponents;
      };

      meta = {
        description = "Rust ${found.label} toolchain";
        platforms = lib.platforms.all;
      };
    };

  # `options.rustfmt`, a second selection, supplies rustfmt and cargo-fmt:
  # a stable compiler with a nightly's formatting options. The result links
  # every other file to the main toolchain, so rustc still finds its own
  # sysroot.
  withRustfmt =
    options:
    let
      main = toolchain (removeAttrs options [ "rustfmt" ] // { withoutRustfmt = true; });
      fmt = toolchain (
        options.rustfmt
        // {
          profile = "minimal";
          components = [ "rustfmt" ];
          targets = [ ];
        }
      );
    in
    pkgs.runCommand "rust-toolchain-${main.version}-rustfmt-${fmt.version}"
      {
        passthru = main.passthru // {
          rustfmt = fmt;
        };
        inherit (main) meta;
      }
      ''
        mkdir -p "$out/bin"
        for entry in ${main}/*; do
          [ "$(basename "$entry")" = bin ] || ln -s "$entry" "$out/"
        done
        ln -s ${main}/bin/* "$out/bin/"
        ln -s ${fmt}/bin/rustfmt ${fmt}/bin/cargo-fmt "$out/bin/"
      '';
in
options: if (options.rustfmt or null) == null then toolchain options else withRustfmt options
