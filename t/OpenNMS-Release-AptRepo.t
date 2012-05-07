$|++;

use strict;
use warnings;

use Cwd;
use File::Path;
use Data::Dumper;
use Test::More;
use OpenNMS::Util v2.6;

BEGIN {
	my $package = `which dpkg 2>/dev/null`;
	if ($? == 0) {
		plan tests => 53;
		use_ok('OpenNMS::Release::DebPackage');
		use_ok('OpenNMS::Release::AptRepo');
	} else {
		plan skip_all => '`dpkg` not found, skipping Debian tests.';
	}
};

my $t = Cwd::abs_path("t");

reset_repos();

my $opennms_18_ro = OpenNMS::Release::AptRepo->new("$t/packages/deb", "opennms-1.8");
isa_ok($opennms_18_ro, 'OpenNMS::Release::AptRepo');

is($opennms_18_ro->base, "$t/packages/deb");
is($opennms_18_ro->release, "opennms-1.8");

my $stable_copy = $opennms_18_ro->copy("$t/testpackages-debrepo/deb");
ok(-d "$t/testpackages-debrepo/deb");
ok(-d "$t/testpackages-debrepo/deb/dists/opennms-1.8/main");
ok(-f "$t/testpackages-debrepo/deb/dists/opennms-1.8/main/binary-all/opennms_1.8.16-1_all.deb");

$stable_copy->delete();
ok(! -d "$t/testpackages-debrepo/deb/opennms-1.8/common");

my ($opennms_18, $nightly_111);

reset_repos();

my $packagelist = $opennms_18->find_all_packages();
is(scalar(@{$packagelist}), 2);

# t/testpackages-debrepo/deb/dists/opennms-1.8/main/binary-i386/iplike-pgsql84_2.0.2-1_i386.deb
my $package = $opennms_18->find_newest_package_by_name('iplike-pgsql84', 'i386');
isa_ok($package, 'OpenNMS::Release::DebPackage');
is($package->name, 'iplike-pgsql84');

$packagelist = $nightly_111->find_all_packages();
is(scalar(@{$packagelist}), 3);

$nightly_111->install_package($package);
ok(-f "$t/testpackages-debrepo/deb/dists/nightly-1.11/main/binary-i386/iplike-pgsql84_2.0.2-1_i386.deb");

$packagelist = $nightly_111->find_all_packages();
is(scalar(@{$packagelist}), 4);

# make sure that we don't get duplicate entries in the package set if we
# install an existing package
$nightly_111->install_package($package);

$packagelist = $nightly_111->find_all_packages();
is(scalar(@{$packagelist}), 4);

($package) = $nightly_111->find_newest_package_by_name('opennms', 'all');
is($package->name, 'opennms');
is($package->version->version, "1.11.0");

$packagelist = $opennms_18->find_all_packages();
is(scalar(@{$packagelist}), 2);

$package = $opennms_18->find_newest_package_by_name('iplike-pgsql84', 'i386');
$nightly_111->share_package($opennms_18, $package);
ok(-f "$t/testpackages-debrepo/deb/dists/nightly-1.11/main/binary-i386/iplike-pgsql84_2.0.2-1_i386.deb" and not -l "$t/testpackages-debrepo/deb/dists/nightly-1.11/main/binary-i386/iplike-pgsql84_2.0.2-1_i386.deb");

$packagelist = $nightly_111->find_newest_packages();
is(scalar(@{$packagelist}), 3);

$packagelist = $nightly_111->find_all_packages();
is(scalar(@{$packagelist}), 4);

$nightly_111->share_package($opennms_18, $package);
ok(-f "$t/testpackages-debrepo/deb/dists/nightly-1.11/main/binary-i386/iplike-pgsql84_2.0.2-1_i386.deb" and not -l "$t/testpackages-debrepo/deb/dists/nightly-1.11/main/binary-i386/iplike-pgsql84_2.0.2-1_i386.deb");

$packagelist = $nightly_111->find_all_packages();
is(scalar(@{$packagelist}), 4);

$packagelist = $nightly_111->find_obsolete_packages();

is(scalar(@{$packagelist}), 1);
is($packagelist->[0]->version->version, "1.0.8");

# subroutine says to not delete any
is($nightly_111->delete_obsolete_packages(sub { return 0 }), 0);
ok(-e "$t/testpackages-debrepo/deb/dists/nightly-1.11/main/binary-i386/iplike-pgsql84_1.0.8-1_i386.deb");

# delete any obsolete by default
is($nightly_111->delete_obsolete_packages(), 1);
ok(! -e "$t/testpackages-debrepo/deb/dists/nightly-1.11/main/binary-i386/iplike-pgsql84_1.0.8-1_i386.deb");

is($nightly_111->delete_obsolete_packages(sub { $_[0]->name ne 'opennms' }), 0);

reset_repos();

$nightly_111->share_all_packages($opennms_18);

$packagelist = $nightly_111->find_all_packages();
is(scalar(@{$packagelist}), 4);

$packagelist = $nightly_111->find_newest_packages();
is(scalar(@{$packagelist}), 3);

$packagelist = $nightly_111->find_obsolete_packages();
is(scalar(@{$packagelist}), 1);
is($packagelist->[0]->name, 'iplike-pgsql84');
is($packagelist->[0]->arch, 'i386');
is($packagelist->[0]->version->version, '1.0.8');

# this should delete the old iplike-1.0.8-1_i386
is($nightly_111->delete_obsolete_packages(), 1);
$package = $nightly_111->find_newest_package_by_name('iplike-pgsql84', 'i386');
is($package->version->version, '2.0.2');
$package = $nightly_111->find_newest_package_by_name('iplike-pgsql84', 'amd64');
is($package->version->version, '1.0.8');

my $copy = $nightly_111->copy("$t/copy");
$package = OpenNMS::Release::DebPackage->new("$t/packages/deb/dists/opennms-1.8/main/binary-all/opennms_1.8.16-1_all.deb");
$copy->install_package($package);
$nightly_111 = $copy->replace($nightly_111);
ok(! -d "$t/copy");
$package = $opennms_18->find_newest_package_by_name('opennms', 'all');
ok(defined $package);
is($package->version->version, "1.8.16");

$package = $nightly_111->find_newest_package_by_name('opennms', 'all');
ok(defined $package);
is($package->version->version, "1.11.0");

$opennms_18->delete;
$nightly_111->delete;

# test excludes

reset_repos();
spit("$t/testpackages-debrepo/deb/dists/nightly-1.11/.exclude-share", "iplike-pgsql84\nopennms\n");
$nightly_111 = OpenNMS::Release::AptRepo->new("$t/testpackages-debrepo/deb", "nightly-1.11");
is(scalar(@{$nightly_111->exclude_share}), 2);
$nightly_111->share_all_packages($opennms_18);
$package = $nightly_111->find_newest_package_by_name('iplike-pgsql84', 'i386');
is($package->version->version, '1.0.8');
$package = $nightly_111->find_newest_package_by_name('iplike-pgsql84', 'amd64');
is($package->version->version, '1.0.8');

# test begin/commit

reset_repos();

ok(! -e "$t/testpackages-debrepo/deb/dists/opennms-1.8/main/binary-i386/iplike-pgsql84_1.0.8-1_i386.deb");
my $temp = $opennms_18->begin();
$temp->install_package(OpenNMS::Release::DebPackage->new("$t/packages/deb/dists/nightly-1.11/main/binary-i386/iplike-pgsql84_1.0.8-1_i386.deb"));
$temp->commit();
ok(-f "$t/testpackages-debrepo/deb/dists/opennms-1.8/main/binary-i386/iplike-pgsql84_1.0.8-1_i386.deb");

# test begin/abort

reset_repos();

ok(! -e "$t/testpackages-debrepo/deb/dists/opennms-1.8/main/binary-i386/iplike-pgsql84_1.0.8-1_i386.deb");
$temp = $opennms_18->begin();
$temp->install_package(OpenNMS::Release::DebPackage->new("$t/packages/deb/dists/nightly-1.11/main/binary-i386/iplike-pgsql84_1.0.8-1_i386.deb"));
$temp->abort();
ok(! -e "$t/testpackages-debrepo/deb/dists/opennms-1.8/main/binary-i386/iplike-pgsql84_1.0.8-1_i386.deb");

# test begin inside begin

reset_repos();

$temp = $opennms_18->begin();
eval {
	$temp = $temp->begin();
};
ok(defined $@);

$opennms_18->delete;
$nightly_111->delete;

sub reset_repos {
	rmtree("$t/testpackages-debrepo");
	$opennms_18 = OpenNMS::Release::AptRepo->new("$t/packages/deb", "opennms-1.8")->copy("$t/testpackages-debrepo/deb");
	$nightly_111 = OpenNMS::Release::AptRepo->new("$t/packages/deb", "nightly-1.11")->copy("$t/testpackages-debrepo/deb");
}

