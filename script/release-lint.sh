#!/bin/bash

set -euo pipefail
IFS=$'\n\t'

WARNING_MODE=0

print_help() {
  cat <<END
usage: $0 [-h] [-w]

  -h     this help
  -w     print warnings but don't exit with an error

END
}

while getopts hw OPT; do
  case "$OPT" in
    h)
      print_help
      exit 0
      ;;
    w)
      WARNING_MODE=1
      ;;
    *)
      printf 'Unknown option: %s' "$OPT"
      exit 1
      ;;
  esac
done
shift "$((OPTIND - 1))"

FAILURES=0

printf "* checking for SNAPSHOT remnants... "
if [ "$(git grep -l -- -SNAPSHOT | grep -v -E '\.md$' | wc -l)" -gt 0 ]; then
  echo "FAILED"
  TEMPFILE="$(mktemp -t release-lint)"
  git grep -l -- -SNAPSHOT | grep -v -E '\.md$' >"${TEMPFILE}"
  echo "  - the following files still contain '-SNAPSHOT':"
  cat "${TEMPFILE}" | while read -r LINE; do
    echo "    * ${LINE}"
  done
  _failed_file_count="$(wc -l < "${TEMPFILE}")"
  FAILURES=$((FAILURES+_failed_file_count))
fi

echo ""
if [ "$WARNING_MODE" -eq 0 ]; then
  echo "ERROR: ${FAILURES} problems were found."
  exit 1
else
  echo "WARNING: ${FAILURES} problems were found. These must be corrected before release."
fi
