#!/usr/bin/env bash
# Write the unit plan of every package the flake in the current directory
# builds with rust-dev-tools.nix, for this system.
#
# Usage: plan-units.sh [PLAN_FILE [NIX_ARGS...]]
#   PLAN_FILE defaults to rust-units.json; NIX_ARGS go to every nix call,
#   such as `--override-input rust-dev-tools path:../rust-dev-tools.nix`.
#
# Each package's `passthru.unitPlan` names its selection; Cargo's unit graph
# for that selection becomes the plan's entry. Entries made from other
# manifests or lockfiles are dropped; entries of other systems are kept.
set -euo pipefail

plan_file="${1:-rust-units.json}"
shift || true
nix_args=("$@")
flake="path:$PWD"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
planner="${RDT_PLANNER:-$here/../rust-cache/plan-units.py}"
system="$(nix eval --impure --raw --expr builtins.currentSystem)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

nix eval "${nix_args[@]}" --json "$flake#packages.$system" --apply '
  packages:
  builtins.filter (entry: entry != null) (
    builtins.attrValues (
      builtins.mapAttrs (
        name: package:
        let
          plan = (package.passthru or { }).unitPlan or null;
        in
        if plan == null then null else { inherit name; } // removeAttrs plan [ "toolchain" ]
      ) packages
    )
  )
' >"$work/selections.json"

count="$(jq length "$work/selections.json")"
if [ "$count" = 0 ]; then
  echo "plan-units: no package in $flake builds with rust-dev-tools.nix" >&2
  exit 1
fi

[ -f "$plan_file" ] || echo '{"version": 1, "plans": {}}' >"$plan_file"
jq --slurpfile selections "$work/selections.json" \
  '.plans |= with_entries(select(.value.inputs as $inputs | $selections[0] | any(.inputs == $inputs)))' \
  "$plan_file" >"$work/plan.json"

declare -A planned
for index in $(seq 0 $((count - 1))); do
  selection="$(jq ".[$index]" "$work/selections.json")"
  name="$(jq -r .name <<<"$selection")"
  key="$(jq -r .key <<<"$selection")"
  inputs="$(jq -r .inputs <<<"$selection")"
  # Packages such as `default` and its alias share a selection.
  [ -n "${planned[$key]:-}" ] && continue
  planned[$key]=1

  cargo="$(nix build "${nix_args[@]}" --no-link --print-out-paths "$flake#packages.$system.$name.passthru.unitPlan.toolchain")/bin/cargo"
  args=(--locked --target "$(jq -r .target <<<"$selection")" --profile "$(jq -r .profile <<<"$selection")")
  features="$(jq -r '.features | join(",")' <<<"$selection")"
  [ -n "$features" ] && args+=(--features "$features")
  [ "$(jq -r .noDefaultFeatures <<<"$selection")" = true ] && args+=(--no-default-features)

  echo "plan-units: $name" >&2
  export __CARGO_TEST_CHANNEL_OVERRIDE_DO_NOT_USE_THIS=nightly
  mapfile -t packages < <(jq -r '.packages[]' <<<"$selection")
  "$cargo" build "${args[@]}" "${packages[@]/#/--package=}" --unit-graph -Z unstable-options >"$work/$key-build.json"
  graphs=("$work/$key-build.json")
  if [ "$(jq -r .doCheck <<<"$selection")" = true ]; then
    mapfile -t checks < <(jq -r '.checkPackages[]' <<<"$selection")
    "$cargo" test --no-run "${args[@]}" "${checks[@]/#/--package=}" --unit-graph -Z unstable-options >"$work/$key-test.json"
    graphs+=("$work/$key-test.json")
  fi
  python3 "$planner" "${graphs[@]}" >"$work/$key-nodes.json"
  jq --arg key "$key" --arg inputs "$inputs" --slurpfile nodes "$work/$key-nodes.json" \
    '.plans[$key] = {inputs: $inputs, nodes: $nodes[0]}' "$work/plan.json" >"$work/next.json"
  mv "$work/next.json" "$work/plan.json"
  echo "plan-units: $name: $(jq length "$work/$key-nodes.json") ready-made crates" >&2
done

jq -S . "$work/plan.json" >"$plan_file"
