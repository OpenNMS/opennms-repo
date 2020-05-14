#!/bin/sh

set -e

CACHEDIR="$1"; shift || :
YUM_REPODIR="$1"; shift || :
APT_REPODIR="$1"; shift || :
OWNER="$1"; shift || :

MYDIR="$(dirname "$0")"
MYDIR="$(cd "$MYDIR"; pwd)"

DL="$MYDIR/download-packagecloud.sh"
RM="$MYDIR/remove-obsolete-rpms.sh"

if [ -z "$OWNER" ]; then
  OWNER="bamboo:repo"
fi

if [ -z "$APT_REPODIR" ]; then
  echo "usage: $0 <cachedir> <yum_repodir> <apt_repodir> [owner]"
  echo ""
  exit 1
fi

mkdir -p "$CACHEDIR"

sign_file() {
  "$MYDIR/sign-package.pl" "$1"
}

rpm_is_signed() {
  __check_file="$1"
  COUNT="$(rpm -q --qf='%{SIGGPG}' -p "$__check_file" | grep -c '(none)')"
  if [ "$COUNT" -eq 0 ]; then
    return 0
  fi
  return 1
}

rpm_sign_unsigned() {
  __searchdir="$1"

  find "$__searchdir" -type f -name \*.rpm | while read -r FILE; do
    if rpm_is_signed "$FILE"; then
      echo "$FILE" is already signed
    else
      sign_file "$FILE"
    fi
  done
}

deb_is_signed() {
  __check_file="$1"
  COUNT="$(dpkg-sig --verify "$__check_file" 2>&1 | grep -c NOSIG)"
  if [ "$COUNT" -eq 0 ]; then
    return 0
  fi
  return 1
}

deb_sign_unsigned() {
  __searchdir="$1"

  find "$__searchdir" -type f -name \*.deb | while read -r FILE; do
    if deb_is_signed "$FILE"; then
      echo "$FILE" is already signed
    else
      sign_file "$FILE"
    fi
  done
}

"$DL" "rpm" "opennms/plugin-stable" "$CACHEDIR/rpm/stable" "$OWNER"
install -d "$YUM_REPODIR/stable/common/packagecloud/"
rsync -al --ignore-existing "$CACHEDIR/rpm/stable/" "$YUM_REPODIR/stable/common/packagecloud/"

"$DL" "rpm" "opennms/plugin-snapshot" "$CACHEDIR/rpm/snapshot" "$OWNER"
"$RM" "opennms_plugin-snapshot" "$CACHEDIR/rpm/snapshot" || :
install -d "$YUM_REPODIR/bleeding/common/packagecloud/"
rsync -al --ignore-existing --delete "$CACHEDIR/rpm/snapshot/" "$YUM_REPODIR/bleeding/common/packagecloud/"

"$DL" "deb" "opennms/plugin-stable"   "$CACHEDIR/deb/stable" "$OWNER"
install -d "$APT_REPODIR/dists/stable/main/binary-all/packagecloud/"
rsync -al --ignore-existing "$CACHEDIR/deb/stable/mirror/packagecloud.io/opennms/plugin-stable/debian/pool/stretch/main/" "$APT_REPODIR/dists/stable/main/binary-all/packagecloud/"

"$DL" "deb" "opennms/plugin-snapshot" "$CACHEDIR/deb/snapshot" "$OWNER"
install -d "$APT_REPODIR/dists/bleeding/main/binary-all/packagecloud/"
rsync -al --ignore-existing --delete "$CACHEDIR/deb/snapshot/mirror/packagecloud.io/opennms/plugin-snapshot/debian/pool/stretch/main/" "$APT_REPODIR/dists/bleeding/main/binary-all/packagecloud/"

rpm_sign_unsigned "$YUM_REPODIR/stable/common/packagecloud"
rpm_sign_unsigned "$YUM_REPODIR/bleeding/common/packagecloud"

deb_sign_unsigned "$APT_REPODIR/dists/stable/main/binary-all/packagecloud"
deb_sign_unsigned "$APT_REPODIR/dists/bleeding/main/binary-all/packagecloud"
