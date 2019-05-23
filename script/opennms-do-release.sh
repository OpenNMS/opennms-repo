#!/bin/bash

CURRENT_VERSION="$1"
PREVIOUS_VERSION="$2"
TYPE="$3"
SIGNINGPASS="$4"

if [ -z "$SIGNINGPASS" ]; then
	echo "usage: $0 <release-version> <previous-version> <horizon|meridian> <signing-password>"
	echo ""
	exit 1
fi

if [ -z "$MAVEN_OPTS" ]; then
	export MAVEN_OPTS="-Xmx4g -XX:ReservedCodeCacheSize=1g -XX:PermSize=512m -XX:MaxPermSize=1g -XX:MaxMetaspaceSize=1g"
fi

if [ -z "$bamboo_buildKey" ]; then
	export bamboo_buildKey="release-${CURRENT_VERSION}"
fi

if [ -e "$HOME/ci/environment" ]; then
	. "$HOME/ci/environment"
fi

set -euo pipefail

CLEAN_REPO=1
TEST=0
ROOT_DIR="${HOME}/opennms-release"
ARTIFACT_DIR="${ROOT_DIR}/artifacts/${CURRENT_VERSION}"
LOG_DIR="${ROOT_DIR}/logs"
LOG_FILE="${LOG_DIR}/${TYPE}-${CURRENT_VERSION}.log"

CURRENT_USER="$(id -un)"
if [ "$TEST" -eq 0 ] && [ "$CURRENT_USER" != "bamboo" ]; then
	echo "ERROR: You must build this as 'bamboo' on one of the Bamboo build systems."
	exit 1
fi

mkdir -p "${LOG_DIR}"
echo "###  INFO: Starting release: $(date)" >"$LOG_FILE"
echo "###  INFO: Release version: ${CURRENT_VERSION}" >>"$LOG_FILE"
echo "###  INFO: Old release version: ${PREVIOUS_VERSION}" >>"$LOG_FILE"

log() {
	echo "*" "$@"
	echo "###  INFO:" "$@" >>"$LOG_FILE"
}

log_error() {
	echo "ERROR:" "$@"
	echo "### ERROR:" "$@" >>"$LOG_FILE"
}

die() {
	log_error "build failed:" "$@"
	echo "See $LOG_FILE for more details."
	echo ""
	exit 1
}

majorVersion() {
	echo "$1" | cut -d. -f1
}

majorMinorVersion() {
	echo "$1" | cut -d. -f1-2
}

pushd_q() {
	pushd "$1" >/dev/null
}

popd_q() {
	popd >/dev/null
}

exec_quiet() {
	set +e
	echo "###  INFO: executing:" "$@" >>"$LOG_FILE"
	"$@" >>"$LOG_FILE" 2>&1
	RET="$?"
	set -e
	return $RET
}

git_clean() {
	exec_quiet git clean -fdx || die "failed to run 'git clean' on repository"
	exec_quiet git prune || die "failed to run 'git prune' on repository"
	exec_quiet git reset --hard HEAD || :
}

if [ $TEST -eq 1 ]; then
	echo '!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!'
	echo 'WARNING: YOU ARE IN TEST MODE!  DEPLOYS WILL BE DIVERTED TO A TEMP DIRECTORY!'
	echo '!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!'
fi

if [ $CLEAN_REPO -eq 0 ]; then
	echo '!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!'
	echo 'WARNING: ~/.m2/repository WILL NOT BE CLEANED OUT FOR THIS RUN!'
	echo '!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!'
fi

MASTER_BRANCH="master-$(majorVersion "${CURRENT_VERSION}")"
RELEASE_BRANCH="release-${CURRENT_VERSION}"
GIT_DIR="${ROOT_DIR}/opennms-source"
DISPLAY_TYPE="$(echo "$TYPE" | perl -p -e 's/\b(.)/\u$1/g')"

COMPILE=("${GIT_DIR}/compile.pl" \
	"-Dmaven.test.skip.exec=true" \
	"-Dbuild.profile=full" \
	"-Prun-expensive-tasks")

DEPLOY_DIR="/mnt/repo-maven/maven2"
if [ $TEST -eq 1 ]; then
	DEPLOY_DIR="/tmp/maven2"
fi
DEPLOY=("${COMPILE[@]}" "-DaltDeploymentRepository=opennms::default::file://${DEPLOY_DIR}")

mkdir -p "${ROOT_DIR}"
mkdir -p "${ARTIFACT_DIR}"
mkdir -p "${ARTIFACT_DIR}/docs"
mkdir -p "${ARTIFACT_DIR}/standalone"

EXISTING_ARTIFACTS="$(find "${ARTIFACT_DIR}" -type f | wc -l)"
if [ "$EXISTING_ARTIFACTS" -gt 0 ]; then
	die "existing artifacts found in ${ARTIFACT_DIR} -- clean it out if you intend to run the release build again"
fi

pushd_q "${ROOT_DIR}"

if [ ! -d "${GIT_DIR}" ]; then
	exec_quiet mkdir -p "${GIT_DIR}"
	pushd_q "${GIT_DIR}"
		log "initializing git repository"
		exec_quiet git init . || die "git init failed"
		exec_quiet git remote add horizon "git@github.com:OpenNMS/opennms.git" || die "unable to add horizon repo to git"
		exec_quiet git remote add meridian "git@github.com:OpenNMS/opennms-prime.git" || die "unable to add meridian repo to git"
	popd_q
fi

pushd_q "${GIT_DIR}"
	log "fetching $TYPE git repository"
	exec_quiet git fetch --prune --tags "$TYPE" || die "failed to refresh/fetch $TYPE repository"

	log "cleaning up git repository"
	git_clean
	exec_quiet git gc --prune=all || :

	REMOTE_EXISTS="$(git branch -a | grep -c -E "remotes/${TYPE}/${MASTER_BRANCH}\$" || :)"
	if [ "$REMOTE_EXISTS" -eq 1 ]; then
		log "checking out ${MASTER_BRANCH}"
		exec_quiet git checkout "${MASTER_BRANCH}" || exec_quiet git checkout -b "${MASTER_BRANCH}" "${TYPE}/${MASTER_BRANCH}" || die "failed to check out master branch ${MASTER_BRANCH}"
	elif [ "$REMOTE_EXISTS" -eq 0 ]; then
		die "${MASTER_BRANCH} does not exist in the ${TYPE} repository -- create it first"
	else
		die "unsure how to deal with ${REMOTE_EXISTS} branches that match 'remotes/${TYPE}/${MASTER_BRANCH}'"
	fi

	log "merging ${RELEASE_BRANCH}"
	exec_quiet git merge --no-edit "${TYPE}/${RELEASE_BRANCH}" || (git status; die "failed to merge ${TYPE}/${RELEASE_BRANCH} to ${MASTER_BRANCH}")

	log "validating documentation"
	DOC_VERSION_COUNT="$(find opennms-doc/releasenotes/src/asciidoc -type f -print0 | xargs -0 cat | grep -c "${CURRENT_VERSION}" || :)"
	if [ "$DOC_VERSION_COUNT" -eq 0 ]; then
		die "the release notes don't contain an entry for ${CURRENT_VERSION}"
		exit 1
	fi
	DEB_VERSION_COUNT="$(grep -c "${CURRENT_VERSION}-" debian/changelog || :)"
	if [ "$TYPE" = "horizon" ] && [ "$DEB_VERSION_COUNT" -eq 0 ]; then
		die "debian/changelog doesn't contain an entry for ${CURRENT_VERSION}"
		exit 1
	fi

	log "setting version to ${CURRENT_VERSION} in POMs and other relevant files"
	find . \
		-type f \
		-print0 \
		-name \*pom.xml \
		-o -name features.xml \
		-o -name \*.md \
		-o -name \*.js \
		-o -name \*.adoc \
		-o -name \*.java \
		-o -name \*.json \
		| xargs -0 perl -pi -e "s,${CURRENT_VERSION}.SNAPSHOT,${CURRENT_VERSION},g"

	log "setting logs to WARN (excluding manager.log and root/defaultThreshold log4j2 entries)"
	# DEBUG -> WARN
	exec_quiet perl -pi -e 's,"DEBUG","WARN",g' opennms-base-assembly/src/main/filtered/etc/log4j2.xml
	exec_quiet perl -pi -e 's,DEBUG,WARN,g' container/karaf/src/main/filtered-resources/etc/org.ops4j.pax.logging.cfg
	# manager.log and root/defaultThreshold back to DEBUG
	# shellcheck disable=SC2016
	exec_quiet perl -pi -e 's,("manager" *value=)"WARN",$1"DEBUG",' opennms-base-assembly/src/main/filtered/etc/log4j2.xml
	exec_quiet perl -pi -e 's,root level="WARN",root level="DEBUG",' opennms-base-assembly/src/main/filtered/etc/log4j2.xml
	exec_quiet perl -pi -e 's,defaultThreshold="WARN",defaultThreshold="DEBUG",' opennms-base-assembly/src/main/filtered/etc/log4j2.xml

	log "making sure there are no straggling SNAPSHOT version references"
	set +eo pipefail
	# shellcheck disable=SC2126
	REMAINDERS="$(grep -r -c -E "${CURRENT_VERSION}.SNAPSHOT" ./* | grep -v -E ':0$' | wc -l)"
	set -eo pipefail
	if [ "$REMAINDERS" -gt 0 ]; then
		die "found ${REMAINDERS} files still referencing ${CURRENT_VERSION}-SNAPSHOT!"
	fi

	log "committing changes: OpenNMS ${DISPLAY_TYPE} ${CURRENT_VERSION}"
	exec_quiet git commit -a -m "OpenNMS ${DISPLAY_TYPE} ${CURRENT_VERSION}"

	if [ $CLEAN_REPO -eq 1 ]; then
		log "cleaning out ~/.m2/repository"
		exec_quiet rm -rf ~/.m2/repository*
	fi

	log "compiling source"
	exec_quiet "${COMPILE[@]}" install || die "failed to run 'compile.pl install' on the source tree"
	log "generating javadoc"
	exec_quiet "${COMPILE[@]}" javadoc:aggregate || die "failed to run 'compile.pl javadoc:aggregate' on the source tree"
	exec_quiet rsync -ar target/site/apidocs/ "${ARTIFACT_DIR}/docs/opennms-${CURRENT_VERSION}-javadoc/"

	log "building XSDs"
	pushd_q opennms-assemblies/xsds
		exec_quiet "${COMPILE[@]}" install || die "failed to run 'compile.pl install' in opennms-assemblies/xsds"
		exec_quiet cp target/org*.tar.gz "${ARTIFACT_DIR}/docs/opennms-${CURRENT_VERSION}-xsds.tar.gz"
	popd_q

	log "building documentation"
	pushd_q opennms-doc
		exec_quiet "${COMPILE[@]}" -T2.0C install || die "failed to build documentation in opennms-doc"
		exec_quiet cp guide-all/target/*.tar.gz "${ARTIFACT_DIR}/docs/opennms-${CURRENT_VERSION}-docs.tar.gz"
	popd_q

	log "building RPMs"
	exec_quiet ./makerpm.sh -s "${SIGNINGPASS}" -a -M 1
	exec_quiet mv target/rpm/SOURCES/*source*.tar.gz "${ARTIFACT_DIR}/"
	MINION_TARBALL="$(ls target/rpm/BUILD/*/opennms-assemblies/minion/target/*minion*.tar.gz || :)"
	if [ -e "${MINION_TARBALL}" ]; then
		exec_quiet mv "${MINION_TARBALL}" "${ARTIFACT_DIR}/standalone/minion-${CURRENT_VERSION}.tar.gz"
	else
		log "WARNING: no minion tarball found -- this should only happen in Meridian builds < 2018"
	fi
	SENTINEL_TARBALL="$(ls target/rpm/BUILD/*/opennms-assemblies/sentinel/target/*sentinel*.tar.gz || :)"
	if [ -e "${SENTINEL_TARBALL}" ]; then
		exec_quiet mv "${SENTINEL_TARBALL}" "${ARTIFACT_DIR}/standalone/sentinel-${CURRENT_VERSION}.tar.gz"
	else
		log "WARNING: no sentinel tarball found -- this should only happen in Meridian builds < 2019 and Horizon builds < 23"
	fi
	exec_quiet mkdir -p "${ARTIFACT_DIR}/rpm"
	exec_quiet mv target/rpm/RPMS/noarch/*.rpm "${ARTIFACT_DIR}/rpm/"
	git_clean

	if [ "$TYPE" = "horizon" ]; then
		log "building Debian packages"
		exec_quiet ./makedeb.sh -a -n -s "${SIGNINGPASS}" -M 1
		exec_quiet mkdir -p "${ARTIFACT_DIR}/deb"
		exec_quiet mv ../*"${CURRENT_VERSION}"*.{deb,dsc,changes,tar.gz} "${ARTIFACT_DIR}/deb/"
		git_clean

		log "building remote poller"
		pushd_q opennms-assemblies/remote-poller-onejar
			exec_quiet "${COMPILE[@]}" -Dinstall.dir=/opt/opennms clean install || die "failed to build remote-poller-onejar"
		popd_q
		pushd_q opennms-assemblies/remote-poller-standalone
			exec_quiet "${COMPILE[@]}" -Dinstall.dir=/opt/opennms clean install || die "failed to build remote-poller-standalone"
			exec_quiet mv "target/org.opennms.assemblies.remote-poller-standalone-${CURRENT_VERSION}-remote-poller.tar.gz" \
				"${ARTIFACT_DIR}/standalone/remote-poller-client-${CURRENT_VERSION}.tar.gz" || die "failed to move the remote poller tarball to the artifacts directory"
		popd_q
		git_clean

		log "deploying to maven repository: ${DEPLOY_DIR}"
		exec_quiet "${DEPLOY[@]}" deploy || die "failed to run compile.pl deploy on the source tree"
		for dir in opennms-assemblies opennms-tools; do
			pushd_q "$dir"
				exec_quiet "${DEPLOY[@]}" -N deploy || die "failed to run compile.pl -N deploy in $dir"
			popd_q
		done

		git_clean
	else
		log "skipping deployment for Meridian"
	fi
popd_q

if [ "$TYPE" = "horizon" ]; then
	if [ ! -d "${ROOT_DIR}/installer" ]; then
		log "checking out installer repository"
		exec_quiet git clone git@github.com:OpenNMS/installer.git
	fi
	pushd_q "${ROOT_DIR}/installer"
		log "cleaning up installer repository"
		git_clean

		log "building installer"
		exec_quiet ln -s "${GIT_DIR}" opennms-build
		pushd_q opennms-build
			git_clean
		popd_q
		exec_quiet ./make-installer.sh -a -M 1
		exec_quiet mv standalone*.zip "${ARTIFACT_DIR}/standalone/"
	popd_q
fi

log "finished building"

popd_q # $ROOT_DIR
