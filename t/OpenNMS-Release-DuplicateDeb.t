$|++;

use strict;
use warnings;

use Cwd;
use File::Path;
use Data::Dumper;
use Test::More;
BEGIN {
	my $package = `which dpkg 2>/dev/null`;
	if ($? == 0) {
		plan tests => 6;
		use_ok('OpenNMS::Release::DebPackage');
		use_ok('OpenNMS::Release::AptRepo');
	} else {
		plan skip_all => '`dpkg` not found, skipping Debian tests.';
	}
};

my $t = Cwd::abs_path("t");

rmtree("$t/testpackages-debrepo");

my ($opennms_18, $nightly_111);

reset_repos();

my $packagelist = $nightly_111->find_all_packages();
is(scalar(@{$packagelist}), 3);

my $package = $opennms_18->find_newest_package_by_name('iplike-pgsql84', 'i386');

$nightly_111->install_package($package);
ok(-f "$t/testpackages-debrepo/deb/dists/nightly-1.11/main/binary-i386/iplike-pgsql84_2.0.2-1_i386.deb");

$packagelist = $nightly_111->find_all_packages();
is(scalar(@{$packagelist}), 4);

# make sure that we don't get duplicate entries in the package set if we
# install an existing package
$nightly_111->install_package($package);

$packagelist = $nightly_111->find_all_packages();
is(scalar(@{$packagelist}), 4);

$opennms_18->delete;
$nightly_111->delete;

sub reset_repos {
	rmtree("$t/testpackages-debrepo/deb");
	$opennms_18 = OpenNMS::Release::AptRepo->new({ base => "$t/packages/deb", release => "opennms-1.8" })->copy("$t/testpackages-debrepo/deb");
	$nightly_111 = OpenNMS::Release::AptRepo->new({ base => "$t/packages/deb", release => "nightly-1.11" })->copy("$t/testpackages-debrepo/deb");
}

