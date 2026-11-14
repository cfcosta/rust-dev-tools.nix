#!/usr/bin/env bash
set -euo pipefail

# Extra arguments are passed to both `nix build` and `nix eval`, for example:
#   scripts/verify-cache.sh --option impure-env ''
# No host-specific Nix setting is changed by default.
if [[ ${1-} == --help ]]; then
  printf '%s\n' 'Usage: scripts/verify-cache.sh [Nix options...]' \
    'Build the exported package-builder cache checks and verify rejected arguments.'
  exit 0
fi

export RDT_ROOT
RDT_ROOT="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
nix_args=("$@")
common='let
  root = builtins.getEnv "RDT_ROOT";
  self = builtins.getFlake root;
  pkgs = import self.inputs.nixpkgs {
    system = builtins.currentSystem;
    overlays = [ self.overlays.default ];
  };
in '

nix build --impure --no-link --print-out-paths "${nix_args[@]}" --expr "$common
  builtins.attrValues (import (root + \"/tests\") { inherit pkgs self; })"

cases="$(nix eval --impure --raw "${nix_args[@]}" --expr "$common
  builtins.concatStringsSep \" \" (builtins.attrNames
    (import (root + \"/tests/packages.nix\") { inherit pkgs self; }).invalid)")"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
for case in $cases; do
  if nix eval --impure --raw "${nix_args[@]}" --expr "$common
    (import (root + \"/tests/packages.nix\") { inherit pkgs self; }).invalid.$case.drvPath" \
    >"$tmp/stdout" 2>"$tmp/stderr"; then
    printf 'FAIL: invalid argument case %s evaluated successfully\n' "$case" >&2
    exit 1
  fi
  # Successful builds above establish the evaluation baseline. Also require a
  # Nix diagnostic rather than accepting a missing command or terminated process.
  if ! grep -Eq 'error:|error message:' "$tmp/stderr"; then
    cat "$tmp/stderr" >&2
    printf 'FAIL: no Nix evaluation error for %s\n' "$case" >&2
    exit 1
  fi
  printf 'Rejected invalid argument case: %s\n' "$case"
done
printf '%s\n' 'PASS: compiled dependency reuse, input invalidation, and builder arguments'
