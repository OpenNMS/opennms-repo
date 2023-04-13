#!/bin/bash

set -euo pipefail
IFS=$'\n\t'

FAILURES=0

printf "* checking for SNAPSHOT remnants... "
if [ "$(git grep -l -- -SNAPSHOT | grep -v -E '\.md$' | wc -l)" -gt 0 ]; then
  echo "FAILED"
  echo "The following files still contain '-SNAPSHOT':"
  git grep -l -- -SNAPSHOT | grep -v -E '\.md$' | while read -r LINE; do
    echo "  * $LINE"
  done
  FAILURES=$((FAILURES++))
fi
