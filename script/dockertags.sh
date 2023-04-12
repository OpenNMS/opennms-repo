#!/bin/bash

set -e
set -o pipefail

if [ $# -lt 1 ]
then
cat << HELP

dockertags  --  list all tags for a Docker image on a remote registry.

EXAMPLE: 
    - list all tags for ubuntu:
       dockertags ubuntu

    - list all opennms horizon tags with 'circleci' in them
       dockertags opennms/horizon circleci

HELP
fi

IMAGE="$1"
SEARCH="$2"

TMPFILE="$(mktemp)"
PAGE=1

get_next() {
  jq -e -r '."next"' < "${TMPFILE}" > /dev/null 2>&1
}

get_results() {
  # echo "fetching page $PAGE"
  wget -q "https://registry.hub.docker.com/v2/repositories/${IMAGE}/tags?page=${PAGE}&page_size=100" -O - > "${TMPFILE}"
}

while
  get_results
  PAGE="$((PAGE+1))"

  if [ -n "$SEARCH" ]; then
    jq -r '."results"[]["name"]' < "$TMPFILE" | grep "$SEARCH"
  else
    jq -r '."results"[]["name"]' < "$TMPFILE"
  fi
  get_next
do true; done
