#!/bin/bash

set -e
set -u
set -o pipefail

DRY_RUN=0
BRANCH_FILE="/tmp/$$.branches"

help() {
	cat <<END
usage: $0 [-h] [-d] <repo> <branch-path>

	-h     this help
	-d     dry run

	repo: the OpenNMS repository to pull branches from
		("opennms", "opennms-helm", etc.)
	branch-path: the path to the directory containing branch data
		("/mnt/repo-yum/branches", etc.)

END
}

cleanup() {
	rm -f "${BRANCH_FILE}" || :
}
trap cleanup EXIT

while getopts 'hd' OPT; do
	case "$OPT" in
		h)
			help
			exit 1
			;;
		d)
			DRY_RUN=1
			;;
		*)
			echo "Unknown option: $OPT"
			echo ""
			help
			exit 1
			;;
	esac
done
shift $((OPTIND - 1))

set +u
if [ -z "$2" ]; then
	help
	exit 1
fi
set -u

REPO="$1"; shift
BRANCH_PATH="$1"; shift

git ls-remote --heads "https://github.com/OpenNMS/${REPO}.git" | awk '{ print $NF }' | sed -e 's,refs/heads/,,' -e 's,/,-,g' > "$BRANCH_FILE"

cd "$BRANCH_PATH"
ls -1 | while read -r BRANCH_DIR; do
	if [ "$(grep -c "$BRANCH_DIR" "$BRANCH_FILE")" -gt 0 ]; then
		echo "keep:   $BRANCH_DIR"
	else
		if [ "$DRY_RUN" -eq 1 ]; then
			echo "delete: $BRANCH_DIR (skipping)"
		else
			echo "delete: $BRANCH_DIR"
			rm -rf "$BRANCH_PATH/$BRANCH_DIR"
		fi
	fi
done
