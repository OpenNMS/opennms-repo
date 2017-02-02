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
		echo ""
		exit 1
	fi
fi

cd "$TOPDIR"
echo "- building source once to prime dependency:tree"
"$TOPDIR/compile.pl" -Dmaven.test.skip.exec=true -Dbuild=all -Pbuild-bamboo install
"$TOPDIR/compile.pl" dependency:tree 2>&1 | grep INFO | grep -E ':(bundle|pom):' 2>&1 | grep -vE '[\+\\]\-' | sed -E 's,^.INFO. ,,' | sed -E 's,:(bundle|pom):.*$,,' | grep -vE '^org.opennms:opennms$' > /tmp/modules.$$
cd opennms-full-assembly
	"$TOPDIR/compile.pl" dependency:tree 2>&1 | grep INFO | grep -E ':(bundle|pom):' 2>&1 | grep -vE '[\+\\]\-' | sed -E 's,^.INFO. ,,' | sed -E 's,:(bundle|pom):.*$,,' >> /tmp/modules.$$
cd -

cat /tmp/modules.$$ | while read PROJECT; do
	echo "- running 'git clean -fdx'"
	git clean -fdx

	printf -- "- cleaning ~/.m2/repository*... "
	rm -rf ~/.m2/repository*
	echo "done"

	echo "- building project: $PROJECT:" "$TOPDIR/compile.pl" -Dmaven.test.skip.exec=true -Dbuild=all -Pbuild-bamboo --projects "$PROJECT" --also-make install
	"$TOPDIR/compile.pl" -Dmaven.test.skip.exec=true -Dbuild=all -Pbuild-bamboo --projects "$PROJECT" --also-make install
done

rm -f /tmp/modules.$$
