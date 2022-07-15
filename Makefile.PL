use inc::Module::Install;

# Define metadata
name           'OpenNMS-Release';
all_from       'lib/OpenNMS/Release.pm';

# Specific dependencies
requires       'DateTime::Format::ISO8601' => undef;
requires       'Expect'                    => 1.20;
requires       'File::NFSLock'             => undef;
requires       'File::ShareDir'            => undef;
requires       'File::Slurp'               => undef;
requires       'Git'                       => undef;
requires       'List::Compare'             => undef;
requires       'Module::Load::Conditional' => undef;
requires       'Net::SFTP::Foreign'        => undef;
requires       'version'                   => undef;
recommends     'JSON::PP'                  => 4.04; # for download-artifacts.pl
recommends     'LWP'                       => 6.43; # for download-artifacts.pl
test_requires  'Test::More'                => undef;

install_script 'script/buildtool.pl';
install_script 'script/clean-opennms-test-databases.pl';
install_script 'script/clean-old-branches.sh';
install_script 'script/create-repo-rpm.pl';
install_script 'script/dependency-monkey.sh';
install_script 'script/deploy-debs.pl';
install_script 'script/deploy-docs.pl';
install_script 'script/deploy-rpms.pl';
install_script 'script/download-artifacts.pl';
install_script 'script/download-packagecloud.sh';
install_script 'script/exec-nfs-exclusive-lock.pl';
install_script 'script/generate-yum-repo-html.pl';
install_script 'script/nightly.pl';
install_script 'script/opennms-release.pl';
install_script 'script/opennms-do-release.sh';
install_script 'script/remove-obsolete-rpms.sh';
install_script 'script/sign-package.pl';
install_script 'script/smoke.pl';
install_script 'script/sync-packagecloud.sh';
install_script 'script/update-apt-repo.pl';
install_script 'script/update-doc-repo.pl';
install_script 'script/update-release-from-master.sh';
install_script 'script/update-sourceforge-repo.pl';
install_script 'script/update-yum-repo.pl';

install_share 'share';

WriteAll;
