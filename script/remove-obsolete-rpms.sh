#!/bin/bash

set -e
set -u
set -o pipefail

DRY_RUN=0
REPOQUERY_OUTPUT="/tmp/$$.repoquery"
RPM_LIST="/tmp/$$.rpms"

cleanup() {
	rm -f "$REPOQUERY_OUTPUT" || :
	rm -f "$RPM_LIST" || :
	echo "* finished deleting old RPMs"
}
trap cleanup EXIT

help() {
	cat <<END
usage: $0 [-h] [-d] <repoid> <rpm-path>

	-h     this help
	-d     dry run

	repoid: the ID of the remote YUM repo ('opennms_plugin-snapshot')
	rpm-path: the local path that contains the mirrored RPMs

END
}

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

REPOID="$1"; shift
RPM_PATH="$1"; shift

repoquery --repoid="$REPOID" --show-duplicates --queryformat='%{name}###%{epoch}###%{version}###%{release}' '*' >"$REPOQUERY_OUTPUT"
find "$RPM_PATH" -type f -name \*.rpm | sort -u >"$RPM_LIST"
RPM_COUNT="$(cat "$RPM_LIST" | wc -l)"

echo "* Scanning $RPM_COUNT RPMs for obsolescence..."

while read -r RPM; do
	BASENAME="$(basename "$RPM")"
	HASH="$(rpm -q --queryformat='%{name}###%{epochnum}###%{version}###%{release}' -p "$RPM")"
	if [ "$(grep -c "^${HASH}\$" "$REPOQUERY_OUTPUT")" -gt 0 ]; then
		echo "keep:   $BASENAME"
	else
		if [ "$DRY_RUN" -eq 1 ]; then
			echo "delete: $BASENAME (skipping)"
		else
			echo "delete: $BASENAME"
			rm -f "$RPM"
		fi
	fi
done <"$RPM_LIST"
