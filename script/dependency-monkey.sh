#!/bin/sh -e

MYDIR=`dirname $0`
TOPDIR=`cd $MYDIR; cd ..; pwd`
TOPDIR="$1"; shift

if [ -z "$TOPDIR" ] || [ ! -d "$TOPDIR" ]; then
	echo "usage: $0 <opennms-directory> [--force]"
	exit 1
fi

echo 'WARNING: THIS SCRIPT WILL DELETE YOUR ~/.m2/repository director(y|ies)!'
if [ "$1" != "--force" ]; then
	printf "Are you sure? [y/N] "
	read APPROVAL
	if [ "$APPROVAL" = "y" ] || [ "$APPROVAL" = "Y" ]; then
		echo "Don't say I didn't warn ya..."
	else
		echo "Dodged that bullet, eh?"
		exit 1
	fi
fi

cd "$TOPDIR"

find * -name pom.xml | grep -vE '(^target/|/target/)' | grep -v opennms-tools | while read POM; do
	printf -- "- cleaning ~/.m2/repository*... "
	rm -rf ~/.m2/repository*
	echo "done"

	echo "- running ./clean.pl"
	./clean.pl

	printf -- "- scanning $POM... "
	POMDIR=`dirname "$POM"`
	PROJECT=""
	pushd $POMDIR >/dev/null 2>&1
		PROJECT=`"$TOPDIR/compile.pl" dependency:tree | grep -E ':(bundle|pom):' 2>&1 | grep -vE '[\+\\]\-' | sed -E 's,^.INFO. ,,' | sed -E 's,:(bundle|pom):.*$,,' | head -n 1`
	popd >/dev/null 2>&1

	if [ -n "$PROJECT" ]; then
		echo "$PROJECT"
		echo "- running:" "$TOPDIR/compile.pl" -Dmaven.test.skip.exec=true -Dbuild=all -Pbuild-bamboo --projects "$PROJECT" --also-make install
		"$TOPDIR/compile.pl" -Dmaven.test.skip.exec=true -Dbuild=all -Pbuild-bamboo --projects "$PROJECT" --also-make install
	else
		echo ""
		echo "ERROR: unable to determine project name from $POM"
		exit 1
	fi
done
