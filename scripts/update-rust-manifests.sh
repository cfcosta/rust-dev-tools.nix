#!/usr/bin/env bash
# Refreshes rust-toolchain/manifests.json, the index of Rust release
# manifests the toolchain builder reads.
#
# Each entry is the sha256 of one dated manifest on static.rust-lang.org,
# taken from the `.sha256` file Rust publishes beside it. The manifest
# itself lists every component's URL and hash, so one hash per release is
# all the index holds. Dated manifests never change, so existing entries
# are kept and only missing ones are fetched.
#
# Usage: scripts/update-rust-manifests.sh [--since YYYY-MM-DD]
#
# Without --since, beta and nightly dates continue from the newest indexed
# one (2025-01-01 for an empty index). --since looks from that date
# instead, which backfills older builds.
set -euo pipefail

root_dir="$(dirname -- "$(dirname -- "$(realpath -- "${BASH_SOURCE[0]}")")")"
index="$root_dir/rust-toolchain/manifests.json"
dist="https://static.rust-lang.org/dist"
since=""

while [ $# -gt 0 ]; do
  case "$1" in
    --since)
      since="$2"
      shift 2
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

[ -f "$index" ] || echo '{"stable":{},"beta":{},"nightly":{}}' > "$index"

fetch() {
  curl --fail --silent --show-error --location --retry 3 "$@"
}

# One stable release: its date from the undated manifest's first bytes,
# then the dated manifest's hash. Prints `stable <version> <date> <sha256>`.
stable_entry() {
  local version="$1" head date sha
  head="$(fetch --range 0-200 "$dist/channel-rust-$version.toml" 2>/dev/null)" || return 0
  date="$(sed -n 's/^date = "\(.*\)"$/\1/p' <<<"$head")"
  [ -n "$date" ] || return 0
  sha="$(fetch "$dist/$date/channel-rust-$version.toml.sha256" 2>/dev/null | cut -d' ' -f1)" || return 0
  if [ -n "$sha" ]; then echo "stable $version $date $sha"; fi
}

# One beta or nightly date. Prints `<channel> <date> <sha256>`, or nothing
# when no build was published that day.
dated_entry() {
  local channel="$1" date="$2" sha
  sha="$(fetch "$dist/$date/channel-rust-$channel.toml.sha256" 2>/dev/null | cut -d' ' -f1)" || return 0
  if [ -n "$sha" ]; then echo "$channel $date $sha"; fi
}

export -f fetch stable_entry dated_entry
export dist

exists() {
  curl --silent --output /dev/null --fail --head "$dist/channel-rust-$1.toml"
}

# Stable versions: every 1.minor.patch from 1.8.0, the first release with
# a v2 manifest, until two minors in a row have no .0 release.
stable_candidates() {
  local minor=8 misses=0 patch
  while [ "$misses" -lt 2 ]; do
    if exists "1.$minor.0"; then
      misses=0
      patch=0
      while exists "1.$minor.$patch"; do
        echo "1.$minor.$patch"
        patch=$((patch + 1))
      done
    else
      misses=$((misses + 1))
    fi
    minor=$((minor + 1))
  done
}

dated_candidates() {
  local channel="$1" start today
  start="$(jq -r --arg c "$channel" '.[$c] | keys | max // empty' "$index")"
  if [ -n "$since" ]; then
    start="$since"
  elif [ -n "$start" ]; then
    start="$(date -u -d "$start + 1 day" +%Y-%m-%d)"
  else
    start="2025-01-01"
  fi
  today="$(date -u +%Y-%m-%d)"
  while [[ "$start" < "$today" || "$start" == "$today" ]]; do
    echo "$channel $start"
    start="$(date -u -d "$start + 1 day" +%Y-%m-%d)"
  done
}

entries="$(mktemp)"
trap 'rm -f "$entries"' EXIT

echo "Listing stable releases ..." >&2
stable_candidates |
  { grep -vxFf <(jq -r '.stable | keys[]' "$index") || true; } |
  xargs -r -P 16 -I{} bash -c 'stable_entry "$1"' _ {} >>"$entries"

echo "Looking for beta and nightly manifests ..." >&2
{ dated_candidates beta; dated_candidates nightly; } |
  { grep -vxFf <(jq -r '(.beta | keys[] | "beta " + .), (.nightly | keys[] | "nightly " + .)' "$index") || true; } |
  xargs -r -P 16 -L 1 bash -c 'dated_entry "$1" "$2"' _ >>"$entries"

jq --raw-input --slurp '
  split("\n") | map(select(length > 0) | split(" "))
' "$entries" |
  jq --slurpfile index "$index" '
    reduce .[] as $e ($index[0];
      if $e[0] == "stable" then .stable[$e[1]] = { date: $e[2], sha256: $e[3] }
      else .[$e[0]][$e[1]] = $e[2] end)
    | .stable |= (to_entries | sort_by(.key | split(".") | map(tonumber)) | from_entries)
    | .beta |= (to_entries | sort_by(.key) | from_entries)
    | .nightly |= (to_entries | sort_by(.key) | from_entries)
  ' >"$index.new"
mv "$index.new" "$index"

echo "Wrote $index" >&2
jq -r '"  stable:  \(.stable | length) (newest \(.stable | keys_unsorted | last))",
       "  beta:    \(.beta | length) (newest \(.beta | keys | last))",
       "  nightly: \(.nightly | length) (newest \(.nightly | keys | last))"' "$index" >&2
