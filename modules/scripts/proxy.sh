#!/usr/bin/env bash

execute() {
	local cmd="$(basename "${0}")-${1}"

	if command -v "${cmd}" &>/dev/null; then
		"${cmd}" "${@:2}"
	else
		echo "Error: Command '$cmd' does not exist."
		exit 1
	fi
}

main() {
	if [ "${#}" -lt 1 ]; then
		echo "Usage: $(basename "${0}") <sub-command>"
		exit 1
	fi

	local subcommand="$1"

	execute "${subcommand}" "${@:2}"
}

main "$@"
