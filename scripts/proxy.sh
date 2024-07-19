#!/usr/bin/env bash

execute() {
	local cmd
	cmd="$(basename "${0}")-${1%"${1##*[![:space:]]}"}"

	if command -v "${cmd}" &>/dev/null; then
		if [ $# -eq 1 ]; then
			"${cmd}"
		else
			"${cmd}" "${@:2}"
		fi
	else
		echo "Error: Command '$cmd' does not exist." >&2
		exit 1
	fi
}

main() {
	if [ $# -eq 0 ]; then
		echo "Usage: $(basename "${0}") <sub-command> [arguments...]" >&2
		exit 1
	fi

	execute "$@"
}

main "$@"
