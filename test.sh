#!/bin/sh

ARGS=("$@")
if [ "${#ARGS[@]}" -eq 0 ]; then
	ARGS=("install")
fi
docker run -it --rm --name my-maven-project -v "$PWD":/opt/build -v "$HOME/.m2:/root/.m2" opennms/maven mvn "${ARGS[@]}"
