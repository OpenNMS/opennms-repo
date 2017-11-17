#!/bin/bash

MYDIR="$(dirname $0)"
MYDIR="$(cd "$MYDIR"; pwd)"
cd "$MYDIR"

GPG_ID="rpmtest@opennms.com"
GPG_PASSWORD="rpm-test"

REPOTOOL="java -jar $(ls -1 java-impl/target/org.opennms.repo.impl-*-jar-with-dependencies.jar | sort -u | tail -n 1) -k ${GPG_ID} -p ${GPG_PASSWORD}"
REPOTOOL="${REPOTOOL} --debug"

RSYNC="rsync -avr --delete"
FROM="/mnt/repo-yum/stable"
TO="/tmp/sample-repo"
POOL="${TO}/pool"

make_meta_pool() {
	DIRNAME="$1"
	mkdir -p "${POOL}/${DIRNAME}/common"
	$REPOTOOL bless --type=rpm "${POOL}/${DIRNAME}/common"
	$REPOTOOL bless --type=rpm-meta "${POOL}/${DIRNAME}"
}

copy_pool() {
	SOURCE="$1"
	DIRNAME="$2"
	DIST="$3"
	if [ -z "$DIRNAME" ]; then
		echo "\$DIRNAME is required!"
		exit 1
	fi
	if [ -z "$DIST" ]; then
		DIST="common"
	fi

	DEST="${POOL}/${DIRNAME}/${DIST}"

	set -e
	echo "* Creating ${DEST}"
	mkdir -p "${DEST}"
	$RSYNC "${SOURCE}/" "${DEST}/"
	set +e
}

init_pool() {
	NAME="$1"
	DIRNAME="$2"
	DIST="$3"
	if [ -z "$DIRNAME" ]; then
		DIRNAME="$(echo "${NAME}" | tr '[:upper:]' '[:lower:]' | sed -e 's, *,,g')"
	fi

	DEST="${POOL}/${DIRNAME}"
	if [ -n "$DIST" ]; then
		DEST="${DEST}/${DIST}"
	fi

	set -e

	if [ -e "${DEST}/.repometa" ]; then
		echo "* ${NAME} is already blessed."
	else
		echo "* Blessing ${NAME}"
		$REPOTOOL bless "${DEST}" "${NAME}"
	fi

	echo "* Normalizing ${NAME}"
	$REPOTOOL normalize "${DEST}"

	echo "* Indexing {NAME}"
	$REPOTOOL index "${DEST}"

	set +e
}

init_meta_pool() {
	NAME="$1"
	DIRNAME="$2"

	make_meta_pool "${DIRNAME}"

	for DIST in common fc19 fc20 fc21 fc22 fc23 fc24 fc25 fc26 rhel5 rhel6 rhel7; do
		if [ -d "${FROM}/${DIST}/${DIRNAME}" ]; then
			copy_pool "${FROM}/${DIST}/${DIRNAME}" "${DIRNAME}" "${DIST}"
			init_pool "${NAME}" "${DIRNAME}" "${DIST}"
		fi
	done

	init_pool "${NAME}" "${DIRNAME}"
}

mvn -Dmaven.test.skip.exec=true install

rm -rf "${TO}"
mkdir -p "${TO}/"

copy_pool "${FROM}/common/helm" "helm"
init_pool "Helm" "helm"

copy_pool "${FROM}/common/jdk" "jdk"
init_pool "JDK" "jdk"

# clean up the OpenNMS source a bit
$RSYNC "${FROM}/common/opennms/" "${TO}/_opennms/"
rm -rf "${TO}/_opennms"/grafana*
mkdir -p "${TO}/_mib2events"
mv "${TO}/_opennms"/mib2events* "${TO}/_mib2events/"
mkdir -p "${TO}/_release"
mv "${TO}/_opennms"/perl-OpenNMS* "${TO}/_release/"

copy_pool "${TO}/_opennms" "opennms"
init_pool "OpenNMS" "opennms"

copy_pool "${TO}/_mib2events" "mib2events"
init_pool "MIB to Events" "mib2events"

copy_pool "${TO}/_release" "opennms-release"
init_pool "OpenNMS Release Tools" "opennms-release"
rm -rf "${TO}"/_*

init_meta_pool "DejaVu Fonts" "dejavu"
init_meta_pool "IPLIKE" "iplike"
init_meta_pool "JICMP" "jicmp"
init_meta_pool "JICMP6" "jicmp6"
init_meta_pool "JRRD" "jrrd"
init_meta_pool "JRRD2" "jrrd2"
init_meta_pool "libsmi" "libsmi"
init_meta_pool "RRDTool" "rrdtool"
