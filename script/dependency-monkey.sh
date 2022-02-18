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

mkdir -p "$WORKDIR"
cd "$WORKDIR"

SOURCEDIR="$WORKDIR/monkey-source"
M2DIR="$WORKDIR/m2"

if [ -d "$SOURCEDIR" ]; then
	# we have an existing checkout, clean it up
	pushd "$SOURCEDIR"
		git clean -fdx
		git fetch origin "$BRANCH"
		git checkout "$BRANCH"
		git reset --hard HEAD
	popd
else
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
	cat <<END >"${M2DIR}/settings.xml"
<settings>
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
	-v "${SOURCEDIR}:/opt/build"
	-v "${M2DIR}:/root/.m2"
	-w "/opt/build"
	-i
	-t
	"$BUILD_ENV"
)
BUILD_ARGS=(
	-Pbuild-bamboo
	-Prun-expensive-tasks
	-Psmoke
	-P'!checkstyle'
	-P'!enable.tarball'
	-Dbuild=all
	-Dbuild.skip.tarball=true
	-Dmaven.test.skip.exec=true
	-DupdatePolicy=never
	--batch-mode
	--fail-at-end
)

reset_m2dir

# on second thought, not gonna do this because reactor order still matters, plugins
# could be pulling in transient dependencies
# echo "- priming m2 cache with plugin dependencies"
# "${DOCKER_CMD[@]}" ./compile.pl "${BUILD_ARGS[@]}" -Dsilent=true dependency:resolve-plugins
# rsync -ar --delete "${M2DIR}/" "${M2DIR}-pristine/"

#echo "- building source once to prime dependency:tree"
#"${DOCKER_CMD[@]}" ./compile.pl "${BUILD_ARGS[@]}" install

echo "- generating list of bundles"
"${DOCKER_CMD[@]}" ./compile.pl "${BUILD_ARGS[@]}" org.opennms.maven.plugins:structure-maven-plugin:1.0:structure
"${DOCKER_CMD[@]}" /bin/bash -c "cat target/structure-graph.json | jq -r '.[] | .groupId + \":\" + .artifactId' | sort -u > target/modules.txt"
mv "${SOURCEDIR}/target/modules.txt" "${WORKDIR}"

while read -r PROJECT; do
	pushd "${SOURCEDIR}"

		echo "- running 'git clean -fdx'"
		git clean -fdx

		printf -- "- cleaning ~/.m2/repository*... "
		reset_m2dir
		echo "done"

	popd

	echo "- building project: $PROJECT"
	"${DOCKER_CMD[@]}" ./compile.pl "${BUILD_ARGS[@]}" --projects "$PROJECT" --also-make install
done < "${WORKDIR}/modules.txt"
