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
TEMPLIST="$(mktemp -t release-lint-XXXXXXXX)"
TEMPEXCLUDES="$(mktemp -t release-lint-excludes-XXXXXXXX)"
TEMPFILTERED="$(mktemp -t release-lint-filtered-XXXXXXXX)"
git grep -l -- -SNAPSHOT | sort -u >"${TEMPLIST}"
if [ -e .release-lint-excludes ]; then
  sort -u < .release-lint-excludes >"${TEMPEXCLUDES}"
else
  printf "" >"${TEMPEXCLUDES}"
fi
comm -2 -3 "${TEMPLIST}" "${TEMPEXCLUDES}" >"${TEMPFILTERED}"

if [ -s "${TEMPFILTERED}" ]; then
  echo "FAILED"
  echo "  - the following files still contain '-SNAPSHOT':"
  cat "${TEMPFILTERED}" | while read -r LINE; do
    echo "    * ${LINE}"
  done
  _failed_file_count="$(wc -l < "${TEMPFILTERED}")"
  FAILURES=$((FAILURES+_failed_file_count))
else
  echo "ok"
fi
rm -f "${TEMPLIST}" "${TEMPEXCLUDES}" "${TEMPFILTERED}"

if [ -e package-lock.json ]; then
  echo "* checking for JavaScript audit failures..."
  if [ ! -d node_modules ]; then
    echo "  * running 'npm ci'"
    npm --no-color ci 2>&1 | grep -v -E 'WARN (deprecated|EBADENGINE)' | while read -r LINE; do
      echo "    * $LINE"
    done
  fi
  echo "  * running 'npm audit --omit dev'"
  TEMPFILE="$(mktemp -t release-lint-XXXXXXXX)"
  if npm audit --omit dev >"${TEMPFILE}" 2>&1; then
    echo "  * no JavaScript audit failures found"
  else
    echo '  ! audit failed:'
    while read -r LINE; do
      echo "    $LINE"
    done < "${TEMPFILE}"
    FAILURES=$((FAILURES++))
  fi
fi

echo ""
if [ "$WARNING_MODE" -eq 0 ]; then
  echo "ERROR: ${FAILURES} problems were found."
  exit 1
else
  echo "WARNING: ${FAILURES} problems were found. These must be corrected before release."
fi
