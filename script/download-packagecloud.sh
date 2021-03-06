#!/bin/bash

MODE="$1"; shift 2>/dev/null || :
REPO="$1"; shift 2>/dev/null || :
REPODIR="$1"; shift 2>/dev/null || :
OWNER="$1"; shift 2>/dev/null || :

# shellcheck disable=SC2001
REPOID="$(echo "$REPO" | sed -e 's,/,_,g')"

MYDIR="$(dirname "$0")"
MYDIR="$(cd "$MYDIR"; pwd)"
ME="$(basename "$0")"

if [ -z "$OWNER" ]; then
  OWNER="bamboo:repo"
fi

if [ -z "$REPODIR" ]; then
  echo "usage: $0 <deb|rpm> <repo> <repodir>"
  echo ""
  echo "ex: $0 deb opennms/plugin-snapshot /tmp/plugin-snapshot"
  echo ""
  exit 1
fi

set -e
set -o pipefail

DEBIAN_DOCKER="debian:stretch-slim"
RPM_DOCKER="centos:7"

CONTAINER="opennms/packagecloud-$MODE-$REPOID"

TEMPDIR="$(mktemp -d -t pcdl.XXXXXX)"
mkdir -p "$TEMPDIR"
mkdir -p "$REPODIR"

echo "* Running $ME in $MODE mode."

fix_ownership() {
  local __fix_path="$1"
  chown -R "$OWNER" "${__fix_path}"
  find "${__fix_path}" -type d -print0 | xargs -0 chmod 2775
  chmod -R ug+rw "${__fix_path}"
}

run_docker() {
  cd "$TEMPDIR"
  docker build -t "$CONTAINER" .
  cd -
  rm -rf "$TEMPDIR"
  mkdir -p "$REPODIR"
  echo docker run --sysctl net.ipv6.conf.all.disable_ipv6=1 --rm -t -v "$MYDIR:/usr/local/bin" -v "$REPODIR:/repo" "$CONTAINER" "/usr/local/bin/$ME" "$MODE-docker" "$REPO" "/repo"
  docker run --sysctl net.ipv6.conf.all.disable_ipv6=1 --rm -t -v "$MYDIR:/usr/local/bin" -v "$REPODIR:/repo" "$CONTAINER" "/usr/local/bin/$ME" "$MODE-docker" "$REPO" "/repo"
}

case "$MODE" in
  deb)
    cat <<END >"$TEMPDIR/Dockerfile"
FROM $DEBIAN_DOCKER
RUN echo "ipv4" > ~/.curlrc
RUN echo 'Acquire::ForceIPv4 "true";' > /etc/apt/apt.conf.d/99force-ipv4
RUN apt-get -y update
RUN apt-get -y --no-install-recommends install ca-certificates curl apt-mirror rsync gnupg apt-transport-https
RUN echo "deb https://packagecloud.io/$REPO/debian/ stretch main" | tee /etc/apt/sources.list.d/opennms-$REPOID-packagecloud.list
RUN curl -L https://packagecloud.io/$REPO/gpgkey | apt-key add -
END
    mkdir -p "${REPODIR}/${REPO}"
    run_docker
    fix_ownership "${REPODIR}/${REPO}"
    ;;
  deb-docker)
    apt-get -y update
    cat <<END >/etc/apt/mirror.list
set base_path /repo
set nthreads 5
set _tilde 0
END
    grep -E '^deb' /etc/apt/sources.list.d/*opennms* >> /etc/apt/mirror.list
    grep -E '^deb ' /etc/apt/sources.list.d/*opennms* | sed -e 's,^deb ,clean ,' >> /etc/apt/mirror.list
    cat /etc/apt/mirror.list
    rsync -al /var/spool/apt-mirror/ /repo/ || exit 1
    apt-mirror || exit 1
    /repo/var/clean.sh || exit 1
    DEB_COUNT="$(find /repo/ -type f -name \*.deb | wc -l)"
    # shellcheck disable=SC2086
    if [ $DEB_COUNT -eq 0 ]; then
      echo "No DEBs found, this is probably wrong."
      exit 1
    fi
    ;;
  rpm)
    cat <<END >"$TEMPDIR/Dockerfile"
FROM $RPM_DOCKER
RUN echo "ipv4" > ~/.curlrc
RUN echo ip_resolve=4 >> /etc/yum.conf
RUN yum -y install createrepo yum-utils curl pygpgme
RUN yum -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
# gross
RUN curl -s "https://packagecloud.io/install/repositories/$REPO/script.rpm.sh" | bash
RUN curl -L -o /tmp/OPENNMS-GPG-KEY https://yum.opennms.org/OPENNMS-GPG-KEY
RUN /usr/bin/rpmkeys --import /tmp/OPENNMS-GPG-KEY
END
    mkdir -p "${REPODIR}/${REPO}"
    run_docker
    fix_ownership "${REPODIR}/${REPO}"
    ;;
  rpm-docker)
    # make sure the cache is 100% up-to-date
    yum -y --verbose clean all
    rm -rf /var/cache/yum/*
    yum -y --verbose --disablerepo='*' --enablerepo="$REPOID" --enablerepo="$REPOID-source" list --showduplicates '*opennms*' '*alec*' '*minion*' '*sentinel*'
    reposync --allow-path-traversal --delete --repoid="$REPOID" --download_path=/repo/ --urls || exit 1
    #reposync --allow-path-traversal --delete --repoid="$REPOID-source" --download_path=/repo/ --urls || exit 1
    reposync --allow-path-traversal --delete --repoid="$REPOID" --download_path=/repo/ || exit 1
    #reposync --allow-path-traversal --delete --repoid="$REPOID-source" --download_path=/repo/ || exit 1
    RPM_COUNT="$(find /repo/ -type f -name \*.rpm | wc -l)"
    # shellcheck disable=SC2086
    if [ $RPM_COUNT -eq 0 ]; then
      echo "No RPMs found, this is probably wrong."
      exit 1
    fi
    ;;
  *)
    echo "Unknown mode."
    exit 1
    ;;
esac
