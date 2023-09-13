#!/usr/bin/env bash

set -e
set -o pipefail

if [ ! -x 'compile.pl' ]; then
    echo 'This script should be run in an OpenNMS source tree!'
    exit 1
fi

#TESTPREFIX="ranger/fake-"
TESTPREFIX=""

ORIGIN="$1"
NEWVERSION="$2"
OLDVERSION="$3"

MAJORVERSION="${NEWVERSION%.*.*}"

if [ -z "${OLDVERSION}" ]; then
    echo "usage: $0 <origin> <newversion> <oldversion>"
    echo ''
    exit 1
fi

# true if the output is empty, false otherwise
if [[ "$(git status --porcelain)" ]]; then
    echo 'ERROR: you have unsaved changes in this repository!'
    echo ''
    exit 1
fi

RELEASE_BRANCH="${TESTPREFIX}release-${MAJORVERSION}.x"
MASTER_BRANCH="${TESTPREFIX}master-${MAJORVERSION}"

echo '* fetching updates from remote repo(s)'
git fetch --all 2>&1 | while read -r LINE; do echo "    $LINE"; done

echo "* checking out release-${MAJORVERSION}.x"
if git for-each-ref --format='%(refname:short)' 'refs/heads/**' | grep -q -E "^${RELEASE_BRANCH}\$"; then
    echo "  * ${RELEASE_BRANCH} exists locally; checking it out and updating it"
    git checkout "${RELEASE_BRANCH}"
    git pull
else
    echo "  * ${RELEASE_BRANCH} does not exist locally; checking it out"
    git checkout -b "${RELEASE_BRANCH}" "${ORIGIN}/${RELEASE_BRANCH}"
fi

echo "* merging master branch master-${MAJORVERSION}"
git merge --no-edit "${ORIGIN}/${MASTER_BRANCH}"

COMMITHASH="$(git log -n 1 '--pretty=format:%H' .version.txt)"
echo "* git commit for version changes was ${COMMITHASH}"
git show -s "${COMMITHASH}"
echo ''
printf '  does this look right? [y/N] '
read -r -n1 CONFIRM
case "$CONFIRM" in
    Y|y)
        echo "  Don't say I didn't warn you."
        ;;
    *)
        echo "Bailing out."
        exit 1
esac

echo "* updating POM and other files to new version"
git show "${COMMITHASH}" | perl -p -e "s,${OLDVERSION}(.SNAPSHOT),${NEWVERSION}\$1,g" | patch -p1 -R

git diff HEAD pom.xml
printf '  does this look right? [y/N] '
read -r -n1 CONFIRM
case "$CONFIRM" in
    Y|y)
        echo "  Alright then."
        ;;
    *)
        echo "Bailing out."
        exit 1
esac
printf '%s-SNAPSHOT' "${NEWVERSION}" > .version.txt

echo "* committing version changes"
git commit -a -m "${OLDVERSION} -> ${NEWVERSION}-SNAPSHOT"

echo ''
# shellcheck disable=SC2016
echo 'You should run `git show` to confirm this did the right thing, and then do "git push". :)'
