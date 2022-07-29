#!/bin/bash

set -e
set -o pipefail

MYDIR="$(dirname "$0")"
MYDIR="$(cd "$MYDIR"; pwd)"

BRANCH="$1"; shift || :
WORKDIR="$1"; shift || :

if [ -z "$BRANCH" ]; then
	echo "usage: $0 <branch> [working_dir]"
	exit 1
fi

if [ -z "$WORKDIR" ]; then
	WORKDIR="$MYDIR/work"
fi

function tearDown() {
	exit_code="$?"
	set +e
	docker kill dependency-monkey       >/dev/null 2>&1 || :
	docker kill dependency-monkey-proxy >/dev/null 2>&1 || :
	sleep 1
	docker rm dependency-monkey         >/dev/null 2>&1 || :
	docker rm dependency-monkey-proxy   >/dev/null 2>&1 || :
	sleep 1
	docker network rm dependency-monkey >/dev/null 2>&1 || :
	return "$exit_code"
}

trap tearDown EXIT

mkdir -p "$WORKDIR"
cd "$WORKDIR"

SOURCEDIR="$WORKDIR/monkey-source"
M2DIR="$WORKDIR/m2"

if [ -d "$SOURCEDIR" ]; then
	echo "- cleaning up source tree and setting to branch=$BRANCH"
	# we have an existing checkout, clean it up
	pushd "$SOURCEDIR" >/dev/null 2>&1
		git clean -fdx
		git fetch origin "$BRANCH"
		if git rev-parse --verify "$BRANCH" >/dev/null 2>&1; then
			git checkout "$BRANCH"
		else
			git checkout -b "$BRANCH" FETCH_HEAD
		fi
		git reset --hard HEAD
	popd >/dev/null 2>&1
else
	echo "- cloning branch $BRANCH from github"
	git clone --depth=1 --branch "$BRANCH" https://github.com/OpenNMS/opennms.git monkey-source
fi

JDK_VERSION="$(grep '<source>' "$SOURCEDIR/pom.xml" | sed -e 's,[[:space:]]*<[^>]*>[[:space:]]*,,g' -e 's,^1\.,,')"
BUILD_ENV=""

case "$JDK_VERSION" in
	8)
		BUILD_ENV="opennms/build-env:8u322b06-3.8.4-b8247"
		;;
	11*)
		BUILD_ENV="opennms/build-env:11.0.14_9-3.8.4-b8249"
		;;
	17*)
		BUILD_ENV="opennms/build-env:17.0.2_8-3.8.4-b8248"
		;;
	*)
		echo "unknown JDK version: $JDK_VERSION"
		exit 1
		;;
esac

reset_m2dir() {
	rm -rf "${M2DIR}"
	mkdir -p "${M2DIR}"
	if [ -d "${M2DIR}-pristine" ]; then
		rsync -ar "${M2DIR}-pristine/" "${M2DIR}/"
	fi
	cat <<END >"${M2DIR}/settings.xml"
<settings>
	<proxies>
		<proxy>
			<id>proxy</id>
			<active>true</active>
			<host>dependency-monkey-proxy</host>
			<port>3128</port>
			<nonProxyHosts>localhost|*.local</nonProxyHosts>
		</proxy>
	</proxies>
	<profiles>
		<profile>
			<id>opennms-repos</id>
			<activation>
				<activeByDefault>true</activeByDefault>
			</activation>
			<repositories>
				<repository>
					<id>opennms-repo</id>
					<name>OpenNMS Repository</name>
					<url>https://maven.opennms.org/content/groups/opennms.org-release/</url>
				</repository>
				<repository>
					<id>central</id>
					<name>Maven Central</name>
					<url>https://repo1.maven.org/maven2/</url>
				</repository>
			</repositories>
			<pluginRepositories>
				<pluginRepository>
					<id>opennms-repo</id>
					<name>OpenNMS Repository</name>
					<url>https://maven.opennms.org/content/groups/opennms.org-release/</url>
				</pluginRepository>
				<pluginRepository>
					<id>central</id>
					<name>Maven Central</name>
					<url>https://repo1.maven.org/maven2/</url>
				</pluginRepository>
			</pluginRepositories>
		</profile>
	</profiles>
</settings>
END
}

DOCKER_CMD=(
	docker run --name=dependency-monkey
	--rm
	--network dependency-monkey
	-v "${SOURCEDIR}:/opt/build"
	-v "${M2DIR}:/root/.m2"
	-w "/opt/build"
	-i
	"$BUILD_ENV"
)
BUILD_ARGS=(
	-Dbuild=all
	-Dbuild.skip.tarball=true
	-DfailIfNoTests=false
	-Djava.security.egd=file:/dev/./urandom
	-Dmaven.test.skip.exec=true
	-Dsmoke=true
	-DupdatePolicy=never
	-Passemblies
	-Pbuild-bamboo
	-Prun-expensive-tasks
	-Psmoke
	-P'!checkstyle'
	-P'!enable.tarball'
	--batch-mode
	--fail-at-end
)

reset_m2dir

echo "- configuring docker network"
docker network create dependency-monkey

echo "- starting up an HTTP proxy"
docker run --network dependency-monkey --name=dependency-monkey-proxy -d -p 3128:3128 datadog/squid

# echo "- priming m2 cache with top-level plugin dependencies"
"${DOCKER_CMD[@]}" ./compile.pl "${BUILD_ARGS[@]}" -Dsilent=true -N dependency:resolve dependency:resolve-plugins
rsync -ar --delete "${M2DIR}/" "${M2DIR}-pristine/"

echo "- generating list of bundles"
"${DOCKER_CMD[@]}" ./compile.pl "${BUILD_ARGS[@]}" org.opennms.maven.plugins:structure-maven-plugin:1.0:structure
"${DOCKER_CMD[@]}" /bin/bash -c "cat target/structure-graph.json | jq -r '.[] | .groupId + \":\" + .artifactId' > target/modules.txt"
mv "${SOURCEDIR}/target/modules.txt" "${WORKDIR}"

PROJECTS=()
while IFS= read -r LINE; do
	PROJECTS+=("$LINE")
done < "${WORKDIR}/modules.txt"

mkdir -p "${WORKDIR}/state"

for PROJECT in "${PROJECTS[@]}"; do
	if [ -e "${WORKDIR}/state/${PROJECT}" ]; then
		continue
	fi
	echo "- building project: $PROJECT"

	pushd "${SOURCEDIR}" >/dev/null 2>&1

		echo "- running 'git clean -fdx'"
		git clean -fdx

		printf -- "- cleaning ~/.m2/repository*... "
		reset_m2dir
		echo "done"

	popd >/dev/null 2>&1

	if ! "${DOCKER_CMD[@]}" ./compile.pl "${BUILD_ARGS[@]}" --projects "$PROJECT" --also-make install; then
		echo "FAILED build: $PROJECT"
		exit 1
	fi

	touch "${WORKDIR}/state/${PROJECT}"
done
