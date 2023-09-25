#!/usr/bin/env bash

set -e

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
cd "${ROOT}" || (
	echo "ERROR: Failed to cd to example path: ${ROOT}"
	exit 1
)

nix flake lock --update-input rust-dev-tools
git update-index --assume-unchanged "${ROOT}/flake.lock"
