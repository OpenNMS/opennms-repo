%{!?_version:%define _version 1.0}
%{!?_release:%define _release 1}

Summary: Yum repository files for %{_tree}/%{_osname} OpenNMS
Name: %{_rpmname}
Version: %{_version}
Release: %{_release}
License: GPL
Group: Development/Tools
URL: http://yum.opennms.org/

Source1: %{_rpmname}-%{_osname}.repo
Source2: %{_rpmname}-%{_osname}.gpg

BuildArch: noarch
BuildRoot: %{_tmppath}/%{name}-%{version}-%{release}-root

%description
Yum repository files for installing OpenNMS %{_tree} on %{_osname}.

%build

%install
install -d -m 755            $RPM_BUILD_ROOT%{_sysconfdir}/yum.repos.d
install -c -m 644 %{SOURCE1} $RPM_BUILD_ROOT%{_sysconfdir}/yum.repos.d/
install -c -m 644 %{SOURCE2} $RPM_BUILD_ROOT%{_sysconfdir}/yum.repos.d/

%clean
if [ "$RPM_BUILD_ROOT" != "/" ]; then
	rm -rf "$RPM_BUILD_ROOT"
fi

%files
%{_sysconfdir}/yum.repos.d/*
