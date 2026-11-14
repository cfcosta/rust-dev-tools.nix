{
  lib,
  craneLib,
  defaults,
}:
{
  src,
  name ? defaults.name,
  pname ? null,
  version ? null,
  cargoLock ? null,
  buildInputs ? [ ],
  nativeBuildInputs ? [ ],
  env ? { },
  buildType ? "release",
  buildFeatures ? [ ],
  buildNoDefaultFeatures ? false,
  checkType ? buildType,
  checkFeatures ? buildFeatures,
  checkNoDefaultFeatures ? buildNoDefaultFeatures,
  doCheck ? true,
  postInstall ? "",
  meta ? { },
  passthru ? { },
}:
let
  mergedEnv = defaults.env // env;
  profile = if buildType == "debug" then "dev" else buildType;
  lockArgs =
    {
      lockFile,
      outputHashes ? { },
    }:
    {
      cargoLock = lockFile;
      inherit outputHashes;
    };

  # Both compilations consume this record; final-only hooks cannot change it.
  sharedArgs =
    {
      inherit src doCheck;
      env = mergedEnv // {
        CARGO_PROFILE = profile;
      };
      buildInputs = defaults.buildInputs ++ buildInputs;
      nativeBuildInputs = defaults.nativeBuildInputs ++ nativeBuildInputs;
      cargoExtraArgs = lib.escapeShellArgs (
        [
          "--locked"
          "--offline"
        ]
        ++ lib.optional buildNoDefaultFeatures "--no-default-features"
        ++ lib.optionals (buildFeatures != [ ]) [
          "--features"
          (lib.concatStringsSep "," buildFeatures)
        ]
      );
    }
    // lib.optionalAttrs (pname != null) { inherit pname; }
    // lib.optionalAttrs (version != null) { inherit version; }
    // lib.optionalAttrs (cargoLock != null) (lockArgs cargoLock);

  cargoArtifacts = craneLib.buildDepsOnly sharedArgs;
in
assert lib.assertMsg (
  builtins.isString buildType && buildType != ""
) "buildRustPackage: buildType must be a nonempty Cargo profile name";
assert lib.assertMsg (
  builtins.isList buildFeatures && builtins.all builtins.isString buildFeatures
) "buildRustPackage: buildFeatures must be a list of feature names";
assert lib.assertMsg
  (
    checkType == buildType
    && checkFeatures == buildFeatures
    && checkNoDefaultFeatures == buildNoDefaultFeatures
  )
  "buildRustPackage: checkType, checkFeatures, and checkNoDefaultFeatures must match the build settings so compiled dependencies can be shared";
assert lib.assertMsg (
  !(mergedEnv ? CARGO_PROFILE)
) "buildRustPackage: env.CARGO_PROFILE is reserved; select the shared profile with buildType";
assert lib.assertMsg (
  !(passthru ? cargoArtifacts)
) "buildRustPackage: passthru.cargoArtifacts is reserved for the generated dependency artifacts";
craneLib.buildPackage (
  sharedArgs
  // {
    inherit
      name
      cargoArtifacts
      postInstall
      meta
      ;
    passthru = passthru // {
      inherit cargoArtifacts;
    };
  }
)
