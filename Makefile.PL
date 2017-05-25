use inc::Module::Install;

# Define metadata
name           'OpenNMS-Release';
all_from       'lib/OpenNMS/Release.pm';

# Specific dependencies
requires       'Git'                       => undef;
requires       'Expect'                    => 1.20;
requires       'File::NFSLock'             => undef;
requires       'File::ShareDir'            => undef;
requires       'File::Slurp'               => undef;
requires       'List::Compare'             => undef;
requires       'Module::Load::Conditional' => undef;
requires       'Net::SFTP::Foreign'        => undef;
requires       'version'                   => undef;
test_requires  'Test::More'                => undef;

install_script 'script/buildtool.pl';
install_script 'script/clean-opennms-test-databases.pl';
install_script 'script/create-repo-rpm.pl';
install_script 'script/dependency-monkey.sh';
install_script 'script/deploy-debs.pl';
install_script 'script/deploy-docs.pl';
install_script 'script/deploy-rpms.pl';
install_script 'script/generate-yum-repo-html.pl';
install_script 'script/nightly.pl';
install_script 'script/opennms-release.pl';
install_script 'script/smoke.pl';
install_script 'script/update-apt-repo.pl';
install_script 'script/update-doc-repo.pl';
install_script 'script/update-sourceforge-repo.pl';
install_script 'script/update-yum-repo.pl';

install_share 'share';

WriteAll;
