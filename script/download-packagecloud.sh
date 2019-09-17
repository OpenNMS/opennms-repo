#!/bin/bash

MODE="$1"; shift 2>/dev/null || :
REPO="$1"; shift 2>/dev/null || :
REPODIR="$1"; shift 2>/dev/null || :

REPOID="$(echo "$REPO" | sed -e 's,/,_,g')"

MYDIR="$(dirname "$0")"
MYDIR="$(cd "$MYDIR"; pwd)"
ME="$(basename "$0")"

if [ -z "$REPODIR" ]; then
  echo "usage: $0 <deb|rpm> <repo> <repodir>"
  echo ""
  echo "ex: $0 deb opennms/plugin-snapshot /tmp/plugin-snapshot"
  echo ""
  exit 1
fi

set -e

CONTAINER="$REPO/packagecloud-$MODE"

TEMPDIR="$(mktemp -d -t pcdl.XXXXXX)"
mkdir -p "$TEMPDIR"
mkdir -p "$REPODIR"

echo "* Running $ME in $MODE mode."

fix_ownership() {
	local __fix_path="$1"
	chown -R bamboo:repo "${__fix_path}"
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
FROM debian:stretch
RUN echo "ipv4" > ~/.curlrc
RUN echo 'Acquire::ForceIPv4 "true";' > /etc/apt/apt.conf.d/99force-ipv4
RUN apt-get -y update
RUN apt-get -y install curl apt-mirror rsync gnupg apt-transport-https
RUN echo "deb https://packagecloud.io/$REPO/debian/ stretch main" | tee /etc/apt/sources.list.d/opennms-packagecloud.list
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
    rsync -al --no-compress /var/spool/apt-mirror/ /repo/
    apt-mirror
    /repo/var/clean.sh
    ;;
  rpm)
    cat <<END >"$TEMPDIR/Dockerfile"
FROM centos:7
RUN echo "ipv4" > ~/.curlrc
RUN echo ip_resolve=4 >> /etc/yum.conf
RUN yum -y install createrepo yum-utils curl pygpgme
RUN yum -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
RUN curl --ipv4 -L -o /etc/yum.repos.d/opennms-packagecloud.repo "https://packagecloud.io/install/repositories/$REPO/config_file.repo?os=centos&dist=7&source=script"
RUN curl -L -o /tmp/OPENNMS-GPG-KEY https://yum.opennms.org/OPENNMS-GPG-KEY
RUN /usr/bin/rpmkeys --import /tmp/OPENNMS-GPG-KEY
RUN yum -q makecache -y --disablerepo='*' --enablerepo="$REPOID"
END
    mkdir -p "${REPODIR}/${REPO}"
    run_docker
    fix_ownership "${REPODIR}/${REPO}"
    ;;
  rpm-docker)
    yum -y --verbose --disablerepo='*' --enablerepo="$REPOID" --enablerepo="$REPOID-source" clean expire-cache
    yum -y --disablerepo='*' --enablerepo="$REPOID" --enablerepo="$REPOID-source" makecache
    reposync --allow-path-traversal --delete --repoid="$REPOID" --download_path=/repo/ --urls
    #reposync --allow-path-traversal --delete --repoid="$REPOID-source" --download_path=/repo/ --urls
    reposync --allow-path-traversal --delete --repoid="$REPOID" --download_path=/repo/
    #reposync --allow-path-traversal --delete --repoid="$REPOID-source" --download_path=/repo/
    ;;
  *)
    echo "Unknown mode."
    exit 1
    ;;
esac
